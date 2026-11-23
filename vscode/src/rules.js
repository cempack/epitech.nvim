// The coding style rules (shared/rules.json) and their explanation as
// Markdown, like :EpitechExplain's float.
"use strict";

const data = require("./data");

const { rules, extensions, severity_rank: severityRank } = data.rules();
const byCode = Object.fromEntries(rules.map((rule) => [rule.code, rule]));

const CHECKERS = { banana: "🍌", grader: "👤", both: "🍌👤" };
const capitalize = (text) => text.charAt(0).toUpperCase() + text.slice(1);

// Markdown for a rule, with the diagnostic's message when there's one.
function markdown(rule, diagnostic) {
  const lang = rule.lang || "c";
  const lines = [`**${rule.code} · ${rule.title}** — ${capitalize(rule.severity)} · ${CHECKERS[rule.checker]}`, ""];
  if (diagnostic) {
    lines.push(`› ${diagnostic.source ? diagnostic.source + ": " : ""}${diagnostic.message}`, "");
  }
  lines.push(rule.summary, "");
  if (rule.notes) {
    lines.push(`*Measured:* ${rule.notes}`, "");
  }
  lines.push("✗", "```" + lang, ...rule.bad, "```", "✓", "```" + lang, ...rule.good, "```");
  return lines.join("\n");
}

module.exports = { rules, extensions, severityRank, byCode, markdown };
