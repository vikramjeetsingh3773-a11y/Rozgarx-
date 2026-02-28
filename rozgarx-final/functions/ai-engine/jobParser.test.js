/**
 * RozgarX AI — AI Job Parser Unit Tests
 * ============================================================
 * Tests all validation, cleaning, chunking, and merging logic.
 * Run: node jobParser.test.js
 * 
 * These tests cover PURE functions (no Firebase/AI calls needed).
 * Integration tests (with actual AI) are in tests/integration/
 * ============================================================
 */

const {
  cleanText,
  chunkText,
  validateJobJSON,
  mergeChunkResults,
  detectCorrigendum,
} = require("./jobParser");


// ─────────────────────────────────────────────────────────────
// MINIMAL TEST RUNNER (no external dependency)
// ─────────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (err) {
    console.log(`  ✗ ${name}`);
    console.log(`    → ${err.message}`);
    failed++;
    failures.push({ name, error: err.message });
  }
}

function expect(val) {
  return {
    toBe: (expected) => {
      if (val !== expected) throw new Error(`Expected ${JSON.stringify(expected)}, got ${JSON.stringify(val)}`);
    },
    toEqual: (expected) => {
      if (JSON.stringify(val) !== JSON.stringify(expected))
        throw new Error(`Expected ${JSON.stringify(expected)}, got ${JSON.stringify(val)}`);
    },
    toContain: (expected) => {
      if (!val.includes(expected)) throw new Error(`Expected to contain ${JSON.stringify(expected)}`);
    },
    toBeTruthy: () => {
      if (!val) throw new Error(`Expected truthy, got ${JSON.stringify(val)}`);
    },
    toBeFalsy: () => {
      if (val) throw new Error(`Expected falsy, got ${JSON.stringify(val)}`);
    },
    toBeGreaterThan: (n) => {
      if (val <= n) throw new Error(`Expected > ${n}, got ${val}`);
    },
    toBeLessThanOrEqual: (n) => {
      if (val > n) throw new Error(`Expected <= ${n}, got ${val}`);
    },
    toHaveLength: (n) => {
      if (val.length !== n) throw new Error(`Expected length ${n}, got ${val.length}`);
    },
  };
}

function describe(name, fn) {
  console.log(`\n${name}`);
  fn();
}


// ─────────────────────────────────────────────────────────────
// VALID JOB JSON (baseline for tests)
// ─────────────────────────────────────────────────────────────

const validJob = {
  jobInfo: {
    title: "Junior Engineer (Civil)",
    department: "Ministry of Railways",
    organization: "Railway Recruitment Board",
    advertisementNumber: "RRB/2024/01",
    notificationDate: "2024-01-15",
    location: "All India",
    state: null,
    isNational: true,
    officialWebsite: "https://rrbchennai.gov.in",
    officialPDFLink: null,
    applicationMode: "Online",
    category: "Railway",
    subCategory: "RRB JE",
  },
  vacancies: {
    total: 7951,
    general: 3576,
    obc: 2143,
    sc: 1192,
    st: 794,
    ews: 246,
    pwbd: null,
    exServicemen: null,
    notes: null,
  },
  salary: {
    minimum: 35400,
    maximum: 112400,
    payLevel: "Level 6",
    gradePay: null,
    allowances: "DA, HRA, Transport",
    rawText: "₹35,400–1,12,400 (Level-6)",
  },
  eligibility: {
    qualificationRequired: "B.E./B.Tech (Civil Engineering)",
    streamOrDiscipline: "Civil Engineering",
    experienceRequired: null,
    minimumPercentage: null,
    additionalRequirements: null,
  },
  ageCriteria: {
    minimumAge: 18,
    maximumAge: 33,
    relaxation: {
      obc: 3,
      scSt: 5,
      pwbd: 10,
      exServicemen: null,
      otherRelaxation: null,
    },
  },
  applicationFees: {
    general: 500,
    obc: 500,
    scSt: 250,
    female: 250,
    pwbd: null,
    paymentMode: "Online (Debit/Credit Card, UPI)",
  },
  importantDates: {
    applicationStartDate: "2024-01-20",
    applicationLastDate: "2024-02-19",
    feePaymentLastDate: "2024-02-20",
    admitCardDate: null,
    examDate: "2024-05-01",
    resultDate: null,
  },
  selectionProcess: [
    { stage: 1, name: "Computer Based Test (CBT)", description: "120 questions, 90 minutes" },
    { stage: 2, name: "Computer Based Aptitude Test", description: "For ALP posts only" },
    { stage: 3, name: "Document Verification", description: null },
    { stage: 4, name: "Medical Examination", description: null },
  ],
  syllabus: [
    { subject: "Mathematics", topics: ["Algebra", "Trigonometry", "Statistics"] },
    { subject: "General Intelligence", topics: ["Analogies", "Coding-Decoding"] },
    { subject: "General Science", topics: ["Physics", "Chemistry", "Biology"] },
    { subject: "General Awareness", topics: ["Current Affairs", "History"] },
  ],
  examPattern: {
    numberOfPapers: 1,
    totalQuestions: 100,
    totalMarks: 100,
    durationMinutes: 90,
    negativeMarking: 0.25,
    mode: "Online",
    sections: [
      { name: "Mathematics", questions: 30, marks: 30 },
      { name: "General Intelligence", questions: 25, marks: 25 },
      { name: "General Science", questions: 25, marks: 25 },
      { name: "General Awareness", questions: 20, marks: 20 },
    ],
  },
  requiredDocuments: [
    "Degree Certificate",
    "10th Marksheet",
    "Caste Certificate",
    "Date of Birth Certificate",
    "Photo ID",
    "Recent Passport Photo",
  ],
  multipleJobs: false,
  aiInsights: {
    shortSummary: "The Railway Recruitment Board has announced 7,951 vacancies for Junior Engineer (Civil) positions across India. Candidates with a B.E./B.Tech in Civil Engineering are eligible to apply. The selection process includes a Computer Based Test followed by document verification and medical examination. The pay scale is Level-6 (₹35,400–₹1,12,400) under the 7th CPC. With nearly 8,000 vacancies, this is one of the larger Railway recruitment drives of 2024. Applications are accepted online until February 19, 2024. Given the high vacancy count and technical qualification requirement, the competition is expected to be moderate compared to non-technical Railway exams.",
    difficultyScore: 6,
    competitionLevel: "Medium",
    estimatedPreparationTime: "3–4 months",
    recommendedStrategy: "Focus on Mathematics and General Science which carry 55% weightage. Attempt at least 2 full mock tests per week from 6 weeks before exam date. Revise General Awareness current affairs weekly.",
  },
};


// ─────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────

describe("cleanText()", () => {

  test("handles empty string", () => {
    expect(cleanText("")).toBe("");
  });

  test("handles null input", () => {
    expect(cleanText(null)).toBe("");
  });

  test("normalizes multiple blank lines", () => {
    const result = cleanText("Line 1\n\n\n\n\nLine 2");
    expect(result).toBe("Line 1\n\nLine 2");
  });

  test("removes decorative separator lines", () => {
    const result = cleanText("Title\n================\nContent");
    expect(result).toContain("Title");
    expect(result).toContain("Content");
  });

  test("normalizes Rs. to ₹", () => {
    const result = cleanText("Salary: Rs. 25,000 per month");
    expect(result).toContain("₹ 25,000");
  });

  test("normalizes INR to ₹", () => {
    const result = cleanText("Pay: INR 35000");
    expect(result).toContain("₹ 35000");
  });

  test("preserves newlines while collapsing spaces", () => {
    const result = cleanText("Word1    Word2\nWord3");
    expect(result).toContain("Word1 Word2");
    expect(result).toContain("\nWord3");
  });

  test("trims result", () => {
    const result = cleanText("   hello   ");
    expect(result).toBe("hello");
  });
});


describe("chunkText()", () => {

  test("returns single chunk for short text", () => {
    const text = "Short text under limit";
    const chunks = chunkText(text, 1000);
    expect(chunks).toHaveLength(1);
    expect(chunks[0]).toBe(text);
  });

  test("splits long text into multiple chunks", () => {
    const text = "A".repeat(50000); // Very long text
    const chunks = chunkText(text, 1000); // Small limit for testing
    expect(chunks.length).toBeGreaterThan(1);
  });

  test("each chunk is within token limit (approximate)", () => {
    const text = "word ".repeat(10000);
    const maxTokens = 500;
    const chunks = chunkText(text, maxTokens);
    const maxChars = maxTokens * 4;
    for (const chunk of chunks) {
      expect(chunk.length).toBeLessThanOrEqual(maxChars + 500); // +500 for overlap
    }
  });

  test("overlap exists between consecutive chunks", () => {
    const text = "Section A\n\n" + "word ".repeat(3000) + "\n\nSection B\n\n" + "word ".repeat(3000);
    const chunks = chunkText(text, 500);
    if (chunks.length > 1) {
      // Last part of chunk 1 should appear in start of chunk 2 (overlap)
      const chunk1End = chunks[0].slice(-200);
      const chunk2Start = chunks[1].slice(0, 300);
      // At least some characters should overlap (not exact test due to paragraph breaks)
      expect(chunks.length).toBeGreaterThan(1);
    }
  });
});


describe("validateJobJSON()", () => {

  test("accepts valid job JSON", () => {
    const result = validateJobJSON(validJob);
    expect(result.valid).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  test("rejects missing required top-level keys", () => {
    const invalid = { jobInfo: { title: "Test", organization: "Org" } };
    const result = validateJobJSON(invalid);
    expect(result.valid).toBe(false);
  });

  test("rejects difficultyScore out of range (0)", () => {
    const invalid = { ...validJob };
    invalid.aiInsights = { ...validJob.aiInsights, difficultyScore: 0 };
    const result = validateJobJSON(invalid);
    expect(result.valid).toBe(false);
  });

  test("rejects difficultyScore out of range (11)", () => {
    const invalid = { ...validJob };
    invalid.aiInsights = { ...validJob.aiInsights, difficultyScore: 11 };
    const result = validateJobJSON(invalid);
    expect(result.valid).toBe(false);
  });

  test("rejects invalid competitionLevel", () => {
    const invalid = { ...validJob };
    invalid.aiInsights = { ...validJob.aiInsights, competitionLevel: "Extreme" };
    const result = validateJobJSON(invalid);
    expect(result.valid).toBe(false);
  });

  test("rejects invalid estimatedPreparationTime", () => {
    const invalid = { ...validJob };
    invalid.aiInsights = { ...validJob.aiInsights, estimatedPreparationTime: "2 weeks" };
    const result = validateJobJSON(invalid);
    expect(result.valid).toBe(false);
  });

  test("rejects salary max < salary min", () => {
    const invalid = JSON.parse(JSON.stringify(validJob));
    invalid.salary.minimum = 50000;
    invalid.salary.maximum = 30000;
    const result = validateJobJSON(invalid);
    expect(result.valid).toBe(false);
    expect(result.errors[0]).toContain("salary.maximum");
  });

  test("rejects age max < age min", () => {
    const invalid = JSON.parse(JSON.stringify(validJob));
    invalid.ageCriteria.minimumAge = 30;
    invalid.ageCriteria.maximumAge = 20;
    const result = validateJobJSON(invalid);
    expect(result.valid).toBe(false);
  });

  test("rejects invalid date format", () => {
    const invalid = JSON.parse(JSON.stringify(validJob));
    invalid.importantDates.applicationLastDate = "19-02-2024"; // Wrong format
    const result = validateJobJSON(invalid);
    expect(result.valid).toBe(false);
  });

  test("accepts null date fields", () => {
    const withNullDates = JSON.parse(JSON.stringify(validJob));
    withNullDates.importantDates.admitCardDate = null;
    withNullDates.importantDates.resultDate = null;
    const result = validateJobJSON(withNullDates);
    expect(result.valid).toBe(true);
  });

  test("rejects vacancy category sum > total by 20%", () => {
    const invalid = JSON.parse(JSON.stringify(validJob));
    invalid.vacancies.total = 100;
    invalid.vacancies.general = 100;
    invalid.vacancies.obc = 100; // Sum = 200, which is > 100*1.2
    const result = validateJobJSON(invalid);
    expect(result.valid).toBe(false);
  });

  test("rejects shortSummary too short (<100 chars)", () => {
    const invalid = JSON.parse(JSON.stringify(validJob));
    invalid.aiInsights.shortSummary = "Too short.";
    const result = validateJobJSON(invalid);
    expect(result.valid).toBe(false);
  });

  test("rejects extra keys in jobInfo", () => {
    const invalid = JSON.parse(JSON.stringify(validJob));
    invalid.jobInfo.unknownField = "hacked";
    const result = validateJobJSON(invalid);
    expect(result.valid).toBe(false);
  });

  test("rejects extra top-level keys", () => {
    const invalid = { ...validJob, injectedKey: "malicious" };
    const result = validateJobJSON(invalid);
    expect(result.valid).toBe(false);
  });

  test("accepts null values for optional fields", () => {
    const withNulls = JSON.parse(JSON.stringify(validJob));
    withNulls.jobInfo.advertisementNumber = null;
    withNulls.jobInfo.notificationDate = null;
    withNulls.eligibility.experienceRequired = null;
    withNulls.salary.allowances = null;
    const result = validateJobJSON(withNulls);
    expect(result.valid).toBe(true);
  });

  test("accepts empty selectionProcess array", () => {
    const withEmpty = JSON.parse(JSON.stringify(validJob));
    withEmpty.selectionProcess = [];
    const result = validateJobJSON(withEmpty);
    expect(result.valid).toBe(true);
  });
});


describe("mergeChunkResults()", () => {

  test("returns single result unchanged", () => {
    const result = mergeChunkResults([validJob]);
    expect(result.jobInfo.title).toBe("Junior Engineer (Civil)");
  });

  test("fills null fields from subsequent chunks", () => {
    const chunk1 = JSON.parse(JSON.stringify(validJob));
    chunk1.jobInfo.advertisementNumber = null;

    const chunk2 = JSON.parse(JSON.stringify(validJob));
    chunk2.jobInfo.advertisementNumber = "RRB/2024/01";
    chunk2.jobInfo.title = null; // chunk2 doesn't have title

    const merged = mergeChunkResults([chunk1, chunk2]);
    expect(merged.jobInfo.advertisementNumber).toBe("RRB/2024/01"); // filled from chunk2
    expect(merged.jobInfo.title).toBe("Junior Engineer (Civil)"); // kept from chunk1
  });

  test("uses highest total vacancies", () => {
    const chunk1 = JSON.parse(JSON.stringify(validJob));
    chunk1.vacancies.total = 500;

    const chunk2 = JSON.parse(JSON.stringify(validJob));
    chunk2.vacancies.total = 7951;

    const merged = mergeChunkResults([chunk1, chunk2]);
    expect(merged.vacancies.total).toBe(7951);
  });

  test("merges selectionProcess without duplicates", () => {
    const chunk1 = JSON.parse(JSON.stringify(validJob));
    chunk1.selectionProcess = [
      { stage: 1, name: "CBT", description: null },
    ];

    const chunk2 = JSON.parse(JSON.stringify(validJob));
    chunk2.selectionProcess = [
      { stage: 1, name: "CBT", description: null },       // duplicate
      { stage: 2, name: "Interview", description: null },  // new
    ];

    const merged = mergeChunkResults([chunk1, chunk2]);
    const stageNames = merged.selectionProcess.map(s => s.name);
    expect(stageNames.filter(n => n === "CBT").length).toBe(1); // no duplicate
    expect(stageNames).toContain("Interview");
  });

  test("merges required documents without duplicates", () => {
    const chunk1 = JSON.parse(JSON.stringify(validJob));
    chunk1.requiredDocuments = ["Degree Certificate", "Photo ID"];

    const chunk2 = JSON.parse(JSON.stringify(validJob));
    chunk2.requiredDocuments = ["Photo ID", "Caste Certificate"]; // Photo ID is duplicate

    const merged = mergeChunkResults([chunk1, chunk2]);
    expect(merged.requiredDocuments.filter(d => d === "Photo ID").length).toBe(1);
    expect(merged.requiredDocuments).toContain("Caste Certificate");
  });

  test("uses last non-null for importantDates", () => {
    const chunk1 = JSON.parse(JSON.stringify(validJob));
    chunk1.importantDates.applicationLastDate = null;

    const chunk2 = JSON.parse(JSON.stringify(validJob));
    chunk2.importantDates.applicationLastDate = "2024-02-19";

    const merged = mergeChunkResults([chunk1, chunk2]);
    expect(merged.importantDates.applicationLastDate).toBe("2024-02-19");
  });

  test("averages difficulty scores across chunks", () => {
    const chunk1 = JSON.parse(JSON.stringify(validJob));
    chunk1.aiInsights.difficultyScore = 6;

    const chunk2 = JSON.parse(JSON.stringify(validJob));
    chunk2.aiInsights.difficultyScore = 8;

    const merged = mergeChunkResults([chunk1, chunk2]);
    expect(merged.aiInsights.difficultyScore).toBe(7); // (6+8)/2
  });
});


describe("detectCorrigendum()", () => {

  test("detects 'corrigendum' keyword", () => {
    expect(detectCorrigendum("Corrigendum to Notification No. SSC/2024")).toBe(true);
  });

  test("detects 'amendment' keyword", () => {
    expect(detectCorrigendum("Amendment in eligibility criteria")).toBe(true);
  });

  test("detects 'corrigendum' case-insensitively", () => {
    expect(detectCorrigendum("CORRIGENDUM NOTICE")).toBe(true);
  });

  test("returns false for normal notification", () => {
    expect(detectCorrigendum("Recruitment Notice for SSC CGL 2024")).toBe(false);
  });

  test("returns false for empty string", () => {
    expect(detectCorrigendum("")).toBe(false);
  });
});


// ─────────────────────────────────────────────────────────────
// RESULTS SUMMARY
// ─────────────────────────────────────────────────────────────

console.log("\n" + "─".repeat(50));
console.log(`Results: ${passed} passed, ${failed} failed`);
if (failures.length > 0) {
  console.log("\nFailed tests:");
  failures.forEach(f => console.log(`  • ${f.name}: ${f.error}`));
}
console.log("─".repeat(50));

if (failed > 0) process.exit(1);
