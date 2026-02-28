/**
 * RozgarX AI — AI Job Parsing Engine
 * ============================================================
 * Production-grade, deterministic, anti-hallucination parser
 * 
 * Pipeline:
 *   raw text → clean → chunk (if large) → AI extract →
 *   merge chunks → validate schema → store OR retry → 
 *   fallback to manual_review
 * 
 * All outputs are strictly validated before touching Firestore.
 * ============================================================
 */

const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const Ajv = require("ajv");
const crypto = require("crypto");
const logger = require("firebase-functions/logger");

const db = getFirestore();
const ajv = new Ajv({ allErrors: true, coerceTypes: false });

// ─────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────

const MAX_TOKENS_PER_CHUNK = 12000;   // ~9,000 words — safe buffer below 16k
const AI_TEMPERATURE       = 0.1;     // Near-deterministic
const AI_MODEL             = "gpt-4o-mini";
const MAX_RETRY_ATTEMPTS   = 2;
const CHARS_PER_TOKEN      = 4;       // Approximate for English text


// ─────────────────────────────────────────────────────────────
// STEP 1: TEXT CLEANER
// ─────────────────────────────────────────────────────────────

/**
 * Normalizes raw scraped/OCR text before sending to AI.
 * Removes noise without destroying meaningful structure.
 */
function cleanText(rawText) {
  if (!rawText || typeof rawText !== "string") return "";

  return rawText
    // Normalize line endings
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")

    // Collapse 3+ blank lines into 2
    .replace(/\n{3,}/g, "\n\n")

    // Remove repeated decorative characters (====, ----, ####)
    .replace(/[=\-#*]{4,}/g, "")

    // Normalize whitespace within lines (but keep newlines)
    .replace(/[ \t]{2,}/g, " ")

    // Remove null bytes and non-printable chars (except newlines/tabs)
    .replace(/[^\x09\x0A\x20-\x7E\u0900-\u097F]/g, " ")

    // Normalize common OCR artifacts
    .replace(/l\/\d/g, (m) => m)       // keep fractions like 1/2
    .replace(/0(?=[A-Z])/g, "O")       // OCR: 0 → O before letters
    .replace(/(?<=[a-z])1(?=[a-z])/g, "l") // OCR: 1 → l between lowercase

    // Normalize Indian number formatting
    .replace(/Rs\.?\s*/gi, "₹")
    .replace(/INR\s*/gi, "₹")

    // Normalize date separators
    .replace(/(\d{2})[-.](\d{2})[-.](\d{4})/g, "$1/$2/$3")

    .trim();
}


// ─────────────────────────────────────────────────────────────
// STEP 2: TEXT CHUNKER
// ─────────────────────────────────────────────────────────────

/**
 * Splits long texts into overlapping chunks.
 * Overlap ensures section boundaries don't lose context.
 */
function chunkText(text, maxTokens = MAX_TOKENS_PER_CHUNK) {
  const maxChars = maxTokens * CHARS_PER_TOKEN;
  const overlapChars = 500; // Overlap to catch cross-boundary data

  if (text.length <= maxChars) {
    return [text]; // No chunking needed
  }

  const chunks = [];
  let start = 0;

  while (start < text.length) {
    let end = start + maxChars;

    // Try to break at a paragraph boundary
    if (end < text.length) {
      const breakPoint = text.lastIndexOf("\n\n", end);
      if (breakPoint > start + maxChars * 0.5) {
        end = breakPoint;
      }
    }

    chunks.push(text.slice(start, end).trim());
    start = end - overlapChars; // Overlap for context continuity
  }

  return chunks;
}


// ─────────────────────────────────────────────────────────────
// STEP 3: AI SYSTEM PROMPT (STRICT)
// ─────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `
You are a precise data extraction engine for Indian government job notifications.

STRICT RULES:
1. Extract ONLY information explicitly present in the provided text.
2. NEVER invent, assume, or infer data not stated in the text.
3. If a field is not found, return null — never guess.
4. Return ONLY valid JSON matching the exact schema provided.
5. No markdown, no explanation, no text before or after the JSON.
6. Dates MUST be in ISO format: YYYY-MM-DD. If only month/year given, use first of month.
7. Numbers must be actual numbers (integers/floats), not strings.
8. difficultyScore must be 1–10 (integer).
9. competitionLevel must be exactly: "Low", "Medium", or "High".
10. If multiple posts exist in one notification, return array under "multipleJobs": true.

You are a data extractor, not a writer. Stay faithful to source text.
`.trim();


// ─────────────────────────────────────────────────────────────
// STEP 4: AI EXTRACTION PROMPT (per chunk)
// ─────────────────────────────────────────────────────────────

function buildExtractionPrompt(text, chunkIndex = 0, totalChunks = 1) {

  const chunkNote = totalChunks > 1
    ? `NOTE: This is chunk ${chunkIndex + 1} of ${totalChunks}. Extract all fields visible in this section. Return null for fields not present in this chunk.`
    : "";

  return `
${chunkNote}

Extract structured data from the following Indian government job notification.

Return ONLY this JSON structure. Do not add any extra keys:

{
  "jobInfo": {
    "title": string | null,
    "department": string | null,
    "organization": string | null,
    "advertisementNumber": string | null,
    "notificationDate": "YYYY-MM-DD" | null,
    "location": string | null,
    "state": string | null,
    "isNational": boolean | null,
    "officialWebsite": string | null,
    "officialPDFLink": string | null,
    "applicationMode": "Online" | "Offline" | "Both" | null,
    "category": "SSC" | "Railway" | "Banking" | "Defence" | "StatePSC" | "Police" | "Teaching" | "Private" | null,
    "subCategory": string | null
  },
  "vacancies": {
    "total": number | null,
    "general": number | null,
    "obc": number | null,
    "sc": number | null,
    "st": number | null,
    "ews": number | null,
    "pwbd": number | null,
    "exServicemen": number | null,
    "notes": string | null
  },
  "salary": {
    "minimum": number | null,
    "maximum": number | null,
    "payLevel": string | null,
    "gradePay": string | null,
    "allowances": string | null,
    "rawText": string | null
  },
  "eligibility": {
    "qualificationRequired": string | null,
    "streamOrDiscipline": string | null,
    "experienceRequired": string | null,
    "minimumPercentage": number | null,
    "additionalRequirements": string | null
  },
  "ageCriteria": {
    "minimumAge": number | null,
    "maximumAge": number | null,
    "relaxation": {
      "obc": number | null,
      "scSt": number | null,
      "pwbd": number | null,
      "exServicemen": number | null,
      "otherRelaxation": string | null
    }
  },
  "applicationFees": {
    "general": number | null,
    "obc": number | null,
    "scSt": number | null,
    "female": number | null,
    "pwbd": number | null,
    "paymentMode": string | null
  },
  "importantDates": {
    "applicationStartDate": "YYYY-MM-DD" | null,
    "applicationLastDate": "YYYY-MM-DD" | null,
    "feePaymentLastDate": "YYYY-MM-DD" | null,
    "admitCardDate": "YYYY-MM-DD" | null,
    "examDate": "YYYY-MM-DD" | null,
    "resultDate": "YYYY-MM-DD" | null
  },
  "selectionProcess": [
    { "stage": number, "name": string, "description": string | null }
  ],
  "syllabus": [
    { "subject": string, "topics": string[] }
  ],
  "examPattern": {
    "numberOfPapers": number | null,
    "totalQuestions": number | null,
    "totalMarks": number | null,
    "durationMinutes": number | null,
    "negativeMarking": number | null,
    "mode": "Online" | "Offline" | "Both" | null,
    "sections": [
      { "name": string, "questions": number | null, "marks": number | null }
    ]
  },
  "requiredDocuments": string[],
  "multipleJobs": false,
  "aiInsights": {
    "shortSummary": string,
    "difficultyScore": number,
    "competitionLevel": "Low" | "Medium" | "High",
    "estimatedPreparationTime": string,
    "recommendedStrategy": string
  }
}

IMPORTANT: 
- shortSummary: 120–200 words, professional, non-promotional, factual
- difficultyScore: integer 1–10 based on vacancy count, exam complexity, stages
- estimatedPreparationTime: one of "1–2 months", "3–4 months", "6+ months"
- recommendedStrategy: 2–3 sentences, concise and actionable
- multipleJobs: set to true only if notification covers MULTIPLE distinct posts

NOTIFICATION TEXT:
─────────────────────────────────────────────────────────────────
${text}
─────────────────────────────────────────────────────────────────
`.trim();
}


// ─────────────────────────────────────────────────────────────
// STEP 5: CALL AI
// ─────────────────────────────────────────────────────────────

async function callAI(prompt, maxTokens = 2000) {
  const apiKey = process.env.OPENAI_API_KEY;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: AI_MODEL,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user",   content: prompt },
      ],
      max_tokens: maxTokens,
      temperature: AI_TEMPERATURE,
      response_format: { type: "json_object" }, // Force JSON mode (GPT-4o)
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`OpenAI API error ${response.status}: ${err}`);
  }

  const data = await response.json();
  return {
    content: data.choices[0].message.content,
    tokensUsed: data.usage?.total_tokens || 0,
    finishReason: data.choices[0].finish_reason,
  };
}


// ─────────────────────────────────────────────────────────────
// STEP 6: JSON SCHEMA VALIDATOR
// ─────────────────────────────────────────────────────────────

const JOB_JSON_SCHEMA = {
  type: "object",
  required: ["jobInfo", "vacancies", "salary", "eligibility", "ageCriteria",
             "applicationFees", "importantDates", "selectionProcess",
             "syllabus", "examPattern", "requiredDocuments", "aiInsights"],
  additionalProperties: false,
  properties: {

    jobInfo: {
      type: "object",
      required: ["title", "organization"],
      additionalProperties: false,
      properties: {
        title:               { type: ["string", "null"] },
        department:          { type: ["string", "null"] },
        organization:        { type: ["string", "null"] },
        advertisementNumber: { type: ["string", "null"] },
        notificationDate:    { type: ["string", "null"], pattern: "^\\d{4}-\\d{2}-\\d{2}$|^null$" },
        location:            { type: ["string", "null"] },
        state:               { type: ["string", "null"] },
        isNational:          { type: ["boolean", "null"] },
        officialWebsite:     { type: ["string", "null"] },
        officialPDFLink:     { type: ["string", "null"] },
        applicationMode:     { type: ["string", "null"], enum: ["Online", "Offline", "Both", null] },
        category:            { type: ["string", "null"] },
        subCategory:         { type: ["string", "null"] },
      }
    },

    vacancies: {
      type: "object",
      additionalProperties: false,
      properties: {
        total:       { type: ["integer", "null"], minimum: 0 },
        general:     { type: ["integer", "null"], minimum: 0 },
        obc:         { type: ["integer", "null"], minimum: 0 },
        sc:          { type: ["integer", "null"], minimum: 0 },
        st:          { type: ["integer", "null"], minimum: 0 },
        ews:         { type: ["integer", "null"], minimum: 0 },
        pwbd:        { type: ["integer", "null"], minimum: 0 },
        exServicemen:{ type: ["integer", "null"], minimum: 0 },
        notes:       { type: ["string", "null"] },
      }
    },

    salary: {
      type: "object",
      additionalProperties: false,
      properties: {
        minimum:    { type: ["number", "null"], minimum: 0 },
        maximum:    { type: ["number", "null"], minimum: 0 },
        payLevel:   { type: ["string", "null"] },
        gradePay:   { type: ["string", "null"] },
        allowances: { type: ["string", "null"] },
        rawText:    { type: ["string", "null"] },
      }
    },

    eligibility: {
      type: "object",
      additionalProperties: false,
      properties: {
        qualificationRequired:  { type: ["string", "null"] },
        streamOrDiscipline:     { type: ["string", "null"] },
        experienceRequired:     { type: ["string", "null"] },
        minimumPercentage:      { type: ["number", "null"], minimum: 0, maximum: 100 },
        additionalRequirements: { type: ["string", "null"] },
      }
    },

    ageCriteria: {
      type: "object",
      additionalProperties: false,
      properties: {
        minimumAge: { type: ["integer", "null"], minimum: 14 },
        maximumAge: { type: ["integer", "null"], minimum: 14, maximum: 65 },
        relaxation: {
          type: "object",
          additionalProperties: false,
          properties: {
            obc:            { type: ["integer", "null"] },
            scSt:           { type: ["integer", "null"] },
            pwbd:           { type: ["integer", "null"] },
            exServicemen:   { type: ["integer", "null"] },
            otherRelaxation:{ type: ["string", "null"] },
          }
        }
      }
    },

    applicationFees: {
      type: "object",
      additionalProperties: false,
      properties: {
        general:     { type: ["number", "null"], minimum: 0 },
        obc:         { type: ["number", "null"], minimum: 0 },
        scSt:        { type: ["number", "null"], minimum: 0 },
        female:      { type: ["number", "null"], minimum: 0 },
        pwbd:        { type: ["number", "null"], minimum: 0 },
        paymentMode: { type: ["string", "null"] },
      }
    },

    importantDates: {
      type: "object",
      additionalProperties: false,
      properties: {
        applicationStartDate: { type: ["string", "null"] },
        applicationLastDate:  { type: ["string", "null"] },
        feePaymentLastDate:   { type: ["string", "null"] },
        admitCardDate:        { type: ["string", "null"] },
        examDate:             { type: ["string", "null"] },
        resultDate:           { type: ["string", "null"] },
      }
    },

    selectionProcess: {
      type: "array",
      items: {
        type: "object",
        required: ["stage", "name"],
        properties: {
          stage:       { type: "integer", minimum: 1 },
          name:        { type: "string" },
          description: { type: ["string", "null"] },
        }
      }
    },

    syllabus: {
      type: "array",
      items: {
        type: "object",
        required: ["subject"],
        properties: {
          subject: { type: "string" },
          topics:  { type: "array", items: { type: "string" } },
        }
      }
    },

    examPattern: {
      type: "object",
      additionalProperties: false,
      properties: {
        numberOfPapers:  { type: ["integer", "null"], minimum: 1 },
        totalQuestions:  { type: ["integer", "null"], minimum: 0 },
        totalMarks:      { type: ["number", "null"], minimum: 0 },
        durationMinutes: { type: ["integer", "null"], minimum: 0 },
        negativeMarking: { type: ["number", "null"], minimum: 0 },
        mode:            { type: ["string", "null"], enum: ["Online", "Offline", "Both", null] },
        sections: {
          type: "array",
          items: {
            type: "object",
            properties: {
              name:      { type: "string" },
              questions: { type: ["integer", "null"] },
              marks:     { type: ["number", "null"] },
            }
          }
        }
      }
    },

    requiredDocuments: {
      type: "array",
      items: { type: "string" }
    },

    multipleJobs: { type: "boolean" },

    aiInsights: {
      type: "object",
      required: ["shortSummary", "difficultyScore", "competitionLevel",
                 "estimatedPreparationTime", "recommendedStrategy"],
      additionalProperties: false,
      properties: {
        shortSummary:            { type: "string", minLength: 100, maxLength: 400 },
        difficultyScore:         { type: "integer", minimum: 1, maximum: 10 },
        competitionLevel:        { type: "string", enum: ["Low", "Medium", "High"] },
        estimatedPreparationTime:{ type: "string", enum: ["1–2 months", "3–4 months", "6+ months"] },
        recommendedStrategy:     { type: "string", minLength: 50 },
      }
    }
  }
};

const validateSchema = ajv.compile(JOB_JSON_SCHEMA);

function validateJobJSON(parsed) {
  const valid = validateSchema(parsed);
  if (!valid) {
    return {
      valid: false,
      errors: validateSchema.errors.map(e => `${e.instancePath} ${e.message}`),
    };
  }

  // Additional business logic validation
  const errors = [];

  // Salary: max should be >= min
  if (parsed.salary?.minimum && parsed.salary?.maximum) {
    if (parsed.salary.maximum < parsed.salary.minimum) {
      errors.push("salary.maximum must be >= salary.minimum");
    }
  }

  // Age: max should be >= min
  if (parsed.ageCriteria?.minimumAge && parsed.ageCriteria?.maximumAge) {
    if (parsed.ageCriteria.maximumAge < parsed.ageCriteria.minimumAge) {
      errors.push("ageCriteria.maximumAge must be >= minimumAge");
    }
  }

  // Date validation
  const dateFields = [
    "applicationStartDate", "applicationLastDate",
    "feePaymentLastDate", "admitCardDate", "examDate", "resultDate"
  ];
  for (const field of dateFields) {
    const val = parsed.importantDates?.[field];
    if (val && !/^\d{4}-\d{2}-\d{2}$/.test(val)) {
      errors.push(`importantDates.${field} must be YYYY-MM-DD, got: ${val}`);
    }
  }

  // Vacancy totals sanity check
  if (parsed.vacancies?.total !== null && parsed.vacancies?.total !== undefined) {
    const categorySum = ["general", "obc", "sc", "st", "ews"].reduce(
      (sum, key) => sum + (parsed.vacancies[key] || 0), 0
    );
    if (categorySum > 0 && categorySum > parsed.vacancies.total * 1.2) {
      errors.push(`vacancies: category sum (${categorySum}) exceeds total (${parsed.vacancies.total}) by >20%`);
    }
  }

  return errors.length > 0
    ? { valid: false, errors }
    : { valid: true, errors: [] };
}


// ─────────────────────────────────────────────────────────────
// STEP 7: CHUNK MERGER
// ─────────────────────────────────────────────────────────────

/**
 * Merges results from multiple chunks.
 * Strategy:
 *   - Non-null wins over null (first found preferred)
 *   - Arrays are merged and deduplicated
 *   - Dates: last non-null wins (later chunks often have full date section)
 *   - Vacancies: highest total wins (most complete chunk)
 *   - aiInsights: generated from first chunk only (full context needed)
 */
function mergeChunkResults(results) {
  if (results.length === 1) return results[0];

  const merged = JSON.parse(JSON.stringify(results[0])); // deep clone

  for (let i = 1; i < results.length; i++) {
    const chunk = results[i];

    // jobInfo: first non-null wins
    for (const key of Object.keys(merged.jobInfo)) {
      if (merged.jobInfo[key] === null && chunk.jobInfo?.[key] !== null) {
        merged.jobInfo[key] = chunk.jobInfo[key];
      }
    }

    // vacancies: prefer highest total (most complete data)
    if ((chunk.vacancies?.total || 0) > (merged.vacancies?.total || 0)) {
      merged.vacancies = chunk.vacancies;
    }

    // salary: first found wins
    if (!merged.salary?.minimum && chunk.salary?.minimum) {
      merged.salary = chunk.salary;
    }

    // eligibility: first non-null wins per field
    for (const key of Object.keys(merged.eligibility || {})) {
      if (!merged.eligibility[key] && chunk.eligibility?.[key]) {
        merged.eligibility[key] = chunk.eligibility[key];
      }
    }

    // ageCriteria: first non-null wins
    if (!merged.ageCriteria?.minimumAge && chunk.ageCriteria?.minimumAge) {
      merged.ageCriteria = chunk.ageCriteria;
    }

    // applicationFees: first non-null wins
    if (!merged.applicationFees?.general && chunk.applicationFees?.general) {
      merged.applicationFees = chunk.applicationFees;
    }

    // importantDates: last non-null wins per field (date sections usually at end)
    for (const key of Object.keys(merged.importantDates || {})) {
      if (chunk.importantDates?.[key]) {
        merged.importantDates[key] = chunk.importantDates[key];
      }
    }

    // selectionProcess: merge arrays, deduplicate by stage name
    if (chunk.selectionProcess?.length > 0) {
      const existingNames = new Set(merged.selectionProcess.map(s => s.name));
      for (const stage of chunk.selectionProcess) {
        if (!existingNames.has(stage.name)) {
          merged.selectionProcess.push(stage);
          existingNames.add(stage.name);
        }
      }
      merged.selectionProcess.sort((a, b) => a.stage - b.stage);
    }

    // syllabus: merge, deduplicate by subject
    if (chunk.syllabus?.length > 0) {
      const existingSubjects = new Set(merged.syllabus.map(s => s.subject));
      for (const item of chunk.syllabus) {
        if (!existingSubjects.has(item.subject)) {
          merged.syllabus.push(item);
          existingSubjects.add(item.subject);
        }
      }
    }

    // examPattern: first non-null wins
    if (!merged.examPattern?.totalQuestions && chunk.examPattern?.totalQuestions) {
      merged.examPattern = chunk.examPattern;
    }

    // requiredDocuments: merge and deduplicate
    if (chunk.requiredDocuments?.length > 0) {
      const existing = new Set(merged.requiredDocuments);
      for (const doc of chunk.requiredDocuments) {
        if (!existing.has(doc)) {
          merged.requiredDocuments.push(doc);
          existing.add(doc);
        }
      }
    }

    // aiInsights: use from first chunk (it sees full beginning context)
    // Override difficulty score with average if significantly different
    if (chunk.aiInsights?.difficultyScore && merged.aiInsights?.difficultyScore) {
      merged.aiInsights.difficultyScore = Math.round(
        (merged.aiInsights.difficultyScore + chunk.aiInsights.difficultyScore) / 2
      );
    }
  }

  return merged;
}


// ─────────────────────────────────────────────────────────────
// STEP 8: MULTI-POST HANDLER
// ─────────────────────────────────────────────────────────────

/**
 * Some notifications advertise multiple posts (e.g. "CGL 2024 includes
 * Assistant Audit Officer, Junior Statistical Officer, Tax Assistant").
 * If AI returns multipleJobs: true, this function requests a
 * second pass to split them into separate job objects.
 */
async function handleMultipleJobs(text) {
  const prompt = `
This government notification contains MULTIPLE distinct job posts.
Extract each post as a SEPARATE entry.

Return JSON array:
[
  {
    "postName": string,
    "vacancies": number | null,
    "eligibility": string | null,
    "payLevel": string | null,
    "ageLimit": string | null
  }
]

Return ONLY the JSON array. No explanation.

NOTIFICATION TEXT:
${text.slice(0, 8000)}
`.trim();

  const result = await callAI(prompt, 1000);
  try {
    return JSON.parse(result.content);
  } catch {
    return null;
  }
}


// ─────────────────────────────────────────────────────────────
// STEP 9: CORRIGENDUM / AMENDMENT DETECTION
// ─────────────────────────────────────────────────────────────

function detectCorrigendum(text) {
  const corrigendumKeywords = [
    "corrigendum", "amendment", "correction", "erratum",
    "modification", "revised", "addendum", "notice no"
  ];
  const lowerText = text.toLowerCase();
  return corrigendumKeywords.some(kw => lowerText.includes(kw));
}


// ─────────────────────────────────────────────────────────────
// MAIN EXPORT: parseJobNotification
// ─────────────────────────────────────────────────────────────

/**
 * Main entry point for the AI Job Parsing Engine.
 * 
 * @param {string} rawText       - Raw text from scraper/PDF extractor
 * @param {string} sourceId      - Source registry ID (for logging)
 * @param {string} jobId         - Firestore job document ID
 * @param {object} metadata      - Additional context (sourceUrl, etc.)
 * @returns {object}             - { success, data, parsingLogId }
 */
async function parseJobNotification(rawText, sourceId, jobId, metadata = {}) {
  const startTime = Date.now();
  const parsingRunId = `parse_${Date.now()}_${crypto.randomBytes(4).toString("hex")}`;
  let totalTokensUsed = 0;
  let attempt = 0;
  let lastError = null;

  logger.info(`[Parser] Starting: ${parsingRunId} | job: ${jobId}`);

  // ── Phase 1: Clean text
  const cleanedText = cleanText(rawText);

  if (cleanedText.length < 100) {
    return await logAndReturn(parsingRunId, jobId, sourceId, "failed",
      "Text too short after cleaning", null, startTime, totalTokensUsed, rawText, metadata);
  }

  // ── Phase 2: Detect corrigendum
  const isCorrigendum = detectCorrigendum(cleanedText);
  if (isCorrigendum) {
    logger.info(`[Parser] Corrigendum detected: ${jobId}`);
    // Still parse, but flag it in metadata
    metadata.isCorrigendum = true;
  }

  // ── Phase 3: Chunk text if large
  const chunks = chunkText(cleanedText);
  logger.info(`[Parser] Text chunks: ${chunks.length} | job: ${jobId}`);

  // ── Phase 4: Extract from each chunk with retry logic
  while (attempt < MAX_RETRY_ATTEMPTS) {
    attempt++;
    const chunkResults = [];

    try {
      for (let i = 0; i < chunks.length; i++) {
        const prompt = buildExtractionPrompt(chunks[i], i, chunks.length);
        const aiResult = await callAI(prompt, 2000);
        totalTokensUsed += aiResult.tokensUsed;

        // Check for truncated response
        if (aiResult.finishReason === "length") {
          logger.warn(`[Parser] Response truncated (chunk ${i + 1}): ${jobId}`);
        }

        // Parse AI JSON response
        const cleaned = aiResult.content.replace(/```json|```/g, "").trim();
        const parsed = JSON.parse(cleaned);
        chunkResults.push(parsed);
      }

      // ── Phase 5: Merge chunk results
      const merged = mergeChunkResults(chunkResults);

      // ── Phase 6: Handle multiple posts
      let multipleJobsData = null;
      if (merged.multipleJobs === true) {
        logger.info(`[Parser] Multiple posts detected: ${jobId}`);
        multipleJobsData = await handleMultipleJobs(cleanedText);
        totalTokensUsed += 500; // approximate
      }

      // ── Phase 7: Schema validation
      const validation = validateJobJSON(merged);

      if (!validation.valid) {
        lastError = `Schema validation failed: ${validation.errors.join("; ")}`;
        logger.warn(`[Parser] Attempt ${attempt} validation failed: ${lastError}`);

        if (attempt >= MAX_RETRY_ATTEMPTS) {
          return await logAndReturn(parsingRunId, jobId, sourceId, "manual_review_required",
            lastError, merged, startTime, totalTokensUsed, rawText, metadata);
        }
        continue; // Retry
      }

      // ── Phase 8: Success — log and return
      const result = {
        ...merged,
        _meta: {
          parsingRunId,
          jobId,
          sourceId,
          isCorrigendum: metadata.isCorrigendum || false,
          multipleJobsData,
          chunksProcessed: chunks.length,
          tokensUsed: totalTokensUsed,
          processingTimeMs: Date.now() - startTime,
          modelVersion: AI_MODEL,
          parsingStatus: "success",
          parsedAt: new Date().toISOString(),
        }
      };

      await logParsing(parsingRunId, jobId, sourceId, "success", null, merged,
        startTime, totalTokensUsed, metadata);

      return { success: true, data: result, parsingLogId: parsingRunId };

    } catch (err) {
      lastError = err.message;
      logger.error(`[Parser] Attempt ${attempt} failed: ${err.message}`);

      if (attempt >= MAX_RETRY_ATTEMPTS) {
        break;
      }

      // Wait before retry (exponential backoff)
      await new Promise(r => setTimeout(r, 1000 * attempt));
    }
  }

  // All retries exhausted
  return await logAndReturn(parsingRunId, jobId, sourceId, "failed",
    lastError, null, startTime, totalTokensUsed, rawText, metadata);
}


// ─────────────────────────────────────────────────────────────
// LOGGING HELPERS
// ─────────────────────────────────────────────────────────────

async function logParsing(runId, jobId, sourceId, status, errorMsg, parsed,
  startTime, tokensUsed, metadata) {
  try {
    await db.collection("parsingLogs").doc(runId).set({
      runId,
      jobId,
      sourceId,
      status,          // "success" | "failed" | "manual_review_required"
      errorMessage: errorMsg || null,
      processingTimeMs: Date.now() - startTime,
      tokensUsed,
      isCorrigendum: metadata?.isCorrigendum || false,
      parsedAt: FieldValue.serverTimestamp(),
      // Store parsed summary (not full JSON to save storage)
      parsedSummary: parsed ? {
        hasTitle: !!parsed.jobInfo?.title,
        hasVacancies: !!parsed.vacancies?.total,
        hasDates: !!parsed.importantDates?.applicationLastDate,
        hasSalary: !!parsed.salary?.minimum,
        difficultyScore: parsed.aiInsights?.difficultyScore,
        competitionLevel: parsed.aiInsights?.competitionLevel,
      } : null,
    });
  } catch (e) {
    logger.error("[logParsing] Failed to write log:", e);
  }
}

async function logAndReturn(runId, jobId, sourceId, status, errorMsg, parsed,
  startTime, tokensUsed, rawText, metadata) {
  await logParsing(runId, jobId, sourceId, status, errorMsg, parsed, startTime, tokensUsed, metadata);

  // Store raw text reference for manual review
  if (status !== "success") {
    try {
      await db.collection("jobs").doc(jobId).update({
        "metadata.parsingStatus": status,
        "metadata.needsReview": true,
        "metadata.parsingRunId": runId,
        "metadata.updatedAt": FieldValue.serverTimestamp(),
      });
    } catch (e) {
      logger.error("[logAndReturn] Failed to update job status:", e);
    }
  }

  return { success: false, error: errorMsg, parsingLogId: runId };
}


// ─────────────────────────────────────────────────────────────
// EXPORTS
// ─────────────────────────────────────────────────────────────

module.exports = {
  parseJobNotification,
  cleanText,
  chunkText,
  validateJobJSON,
  mergeChunkResults,
  detectCorrigendum,
  // Exported for unit testing
  buildExtractionPrompt,
  JOB_JSON_SCHEMA,
};
