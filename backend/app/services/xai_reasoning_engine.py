"""
XAI (Explainable AI) Reasoning Engine
Transforms raw detection results into human-readable, audit-grade explanations
"""
import hashlib
import json
from typing import Dict, Any, List, Optional
from dataclasses import dataclass, asdict
from datetime import datetime
from statistics import mean


@dataclass
class ReasoningEntry:
    """Single flag explanation entry"""
    flag_id: str
    flag_type: str
    severity: str
    title: str
    plain_explanation: str
    technical_detail: str
    evidence: Dict
    suggestion: str
    confidence_impact: float


@dataclass
class LineItemDeepDive:
    """Deep dive explanation for flagged line item"""
    line_index: int
    item_description: str
    why_flagged: str
    key_numbers: Dict[str, float]
    human_action: str


@dataclass
class AuditEntry:
    """Audit trail metadata"""
    analysis_timestamp: str
    engine_version: str
    total_flags_raised: int
    critical_flags: int
    warning_flags: int
    info_flags: int
    rules_checks_run: int
    line_items_analyzed: int
    anomalous_line_items: int
    final_verdict: str
    confidence_score: float
    score_breakdown: Dict[str, float]
    top_risk_factors: List[str]
    reviewer_action_required: bool
    exported_by: str
    chain_of_reasoning_hash: str


@dataclass
class XAIReport:
    """Complete XAI explanation report"""
    executive_summary: str
    reasoning_log: List[Dict]
    line_item_deep_dive: List[Dict]
    audit_entry: Dict


class XAIReasoningEngine:
    """
    Explainable AI Reasoning Engine
    Transforms detection results into human-readable explanations
    """
    
    VERSION = "HybridDetect-v1.0 + XAI-v1.0"
    
    # Flag type mappings
    FLAG_TYPES = {
        "SUBTOTAL + TAX = TOTAL": "MATH_ERROR",
        "LINE ITEM SUM = SUBTOTAL": "MATH_ERROR",
        "LINE CALCULATIONS": "MATH_ERROR",
        "INVOICE DATE LOGIC": "DATE_ANOMALY",
        "INVOICE NUMBER PATTERN": "PATTERN_ANOMALY",
        "CURRENCY CONSISTENCY": "CURRENCY_ERROR",
        "TAX RATE SANITY": "TAX_ANOMALY",
        "ZERO OR NEGATIVE VALUES": "MATH_ERROR",
        "ROUND NUMBER ANOMALY": "PATTERN_ANOMALY",
        "FIELD COMPLETENESS": "FIELD_MISSING"
    }
    
    def __init__(self):
        self.flag_counter = 0
        
    def generate_report(self, detection_result: Dict[str, Any]) -> XAIReport:
        """
        Generate complete XAI report from detection results
        """
        self.flag_counter = 0
        
        # Generate all sections
        executive_summary = self._generate_executive_summary(detection_result)
        reasoning_log = self._generate_reasoning_log(detection_result)
        line_item_deep_dive = self._generate_line_item_deep_dive(detection_result)
        audit_entry = self._generate_audit_entry(detection_result, reasoning_log, line_item_deep_dive)
        
        return XAIReport(
            executive_summary=executive_summary,
            reasoning_log=[self._entry_to_dict(e) for e in reasoning_log],
            line_item_deep_dive=[self._dive_to_dict(d) for d in line_item_deep_dive],
            audit_entry=self._audit_to_dict(audit_entry)
        )
    
    def _generate_executive_summary(self, result: Dict) -> str:
        """Generate 2-4 sentence plain-English summary for finance manager"""
        verdict = result.get('verdict', 'UNKNOWN')
        confidence = result.get('final_confidence_score', 0)
        rules_checks = result.get('rules_checks', [])
        line_anomalies = result.get('line_item_anomalies', [])
        
        # Find critical issues
        critical_issues = [c for c in rules_checks if not c.get('passed') and c.get('severity') == 'critical']
        warning_issues = [c for c in rules_checks if not c.get('passed') and c.get('severity') == 'warning']
        flagged_lines = [a for a in line_anomalies if a.get('flagged')]
        
        sentences = []
        
        # Opening sentence with score
        if verdict == "LIKELY GENUINE":
            sentences.append(
                f"This invoice scored {confidence:.0f}% on the forgery detection scale, "
                f"indicating it is LIKELY GENUINE with strong confidence."
            )
        elif verdict == "SUSPICIOUS - REVIEW REQUIRED":
            sentences.append(
                f"This invoice scored {confidence:.0f}% on the forgery detection scale, "
                f"indicating SUSPICIOUS ACTIVITY that requires manual review."
            )
        else:
            sentences.append(
                f"This invoice scored {confidence:.0f}% on the forgery detection scale, "
                f"indicating HIGH FORGERY RISK. Immediate investigation is recommended."
            )
        
        # Mention critical issues
        issue_descriptions = []
        
        if critical_issues:
            top_critical = critical_issues[:2]
            for issue in top_critical:
                note = issue.get('note', '')
                check_name = issue.get('check_name', 'Unknown issue')
                
                if "math" in note.lower() or "total" in check_name.lower():
                    issue_descriptions.append("mathematical discrepancies in the financial totals")
                elif "date" in check_name.lower():
                    issue_descriptions.append("impossible timeline with invoice date in the future")
                elif "zero" in check_name.lower():
                    issue_descriptions.append("zero or negative values in financial fields")
                elif "tax" in check_name.lower():
                    issue_descriptions.append("abnormal tax rate outside normal ranges")
                else:
                    issue_descriptions.append(note.split('.')[0] if note else check_name.lower())
        
        if flagged_lines:
            line_desc = f"{len(flagged_lines)} statistically unusual line item(s)"
            if len(flagged_lines) == 1:
                desc = flagged_lines[0].get('description', 'item')
                line_desc = f"one statistically unusual line item ('{desc}')"
            issue_descriptions.append(line_desc)
        
        if warning_issues and not critical_issues:
            top_warning = warning_issues[0]
            note = top_warning.get('note', '')
            if note:
                issue_descriptions.append(note.split('.')[0].lower())
        
        if issue_descriptions:
            issues_text = ", ".join(issue_descriptions[:2])
            if len(issue_descriptions) > 2:
                issues_text += f", and {len(issue_descriptions) - 2} other concerns"
            
            if verdict == "LIKELY GENUINE":
                sentences.append(f"Minor observations include: {issues_text}.")
            else:
                sentences.append(f"Key issues identified: {issues_text}.")
        
        # Action recommendation
        recommended_action = result.get('recommended_action', '')
        if verdict == "LIKELY GENUINE":
            sentences.append("The invoice may proceed with standard processing, though a quick review of the flagged items is advised.")
        elif verdict == "SUSPICIOUS - REVIEW REQUIRED":
            sentences.append("Manual review by a senior auditor is strongly recommended before approving payment.")
        else:
            sentences.append("STOP - Do not process payment without thorough investigation and vendor verification.")
        
        return " ".join(sentences)
    
    def _generate_reasoning_log(self, result: Dict) -> List[ReasoningEntry]:
        """Generate per-flag explanations for all failed checks and anomalies"""
        entries = []
        
        # Process failed rules checks
        rules_checks = result.get('rules_checks', [])
        for check in rules_checks:
            if not check.get('passed'):
                entry = self._create_reasoning_entry_from_check(check)
                if entry:
                    entries.append(entry)
        
        # Process flagged line items
        line_anomalies = result.get('line_item_anomalies', [])
        for anomaly in line_anomalies:
            if anomaly.get('flagged'):
                entry = self._create_reasoning_entry_from_anomaly(anomaly)
                if entry:
                    entries.append(entry)
        
        # Sort by severity: CRITICAL first, then WARNING, then INFO
        severity_order = {"CRITICAL": 0, "WARNING": 1, "INFO": 2}
        entries.sort(key=lambda e: severity_order.get(e.severity, 3))
        
        return entries
    
    def _create_reasoning_entry_from_check(self, check: Dict) -> Optional[ReasoningEntry]:
        """Create reasoning entry from a failed rules check"""
        self.flag_counter += 1
        check_name = check.get('check_name', 'Unknown Check')
        severity = check.get('severity', 'warning').upper()
        note = check.get('note', '')
        expected = check.get('expected_value')
        found = check.get('found_value')
        
        # Determine flag type
        flag_type = self.FLAG_TYPES.get(check_name, "PATTERN_ANOMALY")
        
        # Generate human-readable title
        title = self._generate_title_from_check(check_name, note)
        
        # Generate plain explanation
        plain_explanation = self._generate_plain_explanation(check_name, note, found)
        
        # Generate technical detail
        technical_detail = self._generate_technical_detail(check_name, expected, found, note)
        
        # Create evidence dict
        evidence = {
            "check_name": check_name,
            "expected": expected,
            "found": found
        }
        
        # Generate actionable suggestion
        suggestion = self._generate_suggestion(check_name, flag_type, found)
        
        # Calculate confidence impact
        confidence_impact = -25 if severity == "CRITICAL" else (-10 if severity == "WARNING" else -3)
        
        return ReasoningEntry(
            flag_id=f"FLAG_{self.flag_counter:03d}",
            flag_type=flag_type,
            severity=severity,
            title=title,
            plain_explanation=plain_explanation,
            technical_detail=technical_detail,
            evidence=evidence,
            suggestion=suggestion,
            confidence_impact=confidence_impact
        )
    
    def _create_reasoning_entry_from_anomaly(self, anomaly: Dict) -> Optional[ReasoningEntry]:
        """Create reasoning entry from a flagged line item anomaly"""
        self.flag_counter += 1
        
        line_idx = anomaly.get('line_index', 0)
        description = anomaly.get('description', f'Line {line_idx + 1}')
        anomaly_score = anomaly.get('anomaly_score', 0)
        z_scores = anomaly.get('z_scores', {})
        unit_price = anomaly.get('unit_price', 0)
        quantity = anomaly.get('quantity', 0)
        line_total = anomaly.get('line_total', 0)
        
        # Determine which z-score is highest
        max_z_field = max(z_scores.items(), key=lambda x: abs(x[1])) if z_scores else ('price_z', 0)
        max_z_field_name, max_z_value = max_z_field
        
        # Generate title
        title = f"Unusual Pricing for '{description}'"
        
        # Generate plain explanation
        if abs(max_z_value) > 2.5:
            deviation = "significantly higher" if max_z_value > 0 else "significantly lower"
            plain_explanation = (
                f"The {self._field_to_plain_name(max_z_field_name)} for '{description}' is "
                f"{deviation} than typical values on this invoice. "
                f"This statistical outlier may indicate an error or fraudulent pricing."
            )
        else:
            plain_explanation = (
                f"The line item '{description}' shows an unusual combination of price, quantity, and total "
                f"that doesn't match typical patterns on this invoice."
            )
        
        # Generate technical detail
        technical_detail = (
            f"Line index={line_idx}, description='{description}', "
            f"anomaly_score={anomaly_score:.3f}, highest_z_field={max_z_field_name}={max_z_value:.3f}. "
            f"Z-scores: price_z={z_scores.get('price_z', 0):.3f}, "
            f"qty_z={z_scores.get('qty_z', 0):.3f}, total_z={z_scores.get('total_z', 0):.3f}. "
            f"Flagged because |z-score| > 2.5 or anomaly_score > 0.6"
        )
        
        # Create evidence
        evidence = {
            "line_index": line_idx,
            "description": description,
            "unit_price": unit_price,
            "quantity": quantity,
            "line_total": line_total,
            "z_scores": z_scores,
            "anomaly_score": anomaly_score
        }
        
        # Generate suggestion
        suggestion = (
            f"Verify the pricing for '{description}' against the vendor's standard rate card "
            f"or previous invoices from this vendor."
        )
        
        return ReasoningEntry(
            flag_id=f"FLAG_{self.flag_counter:03d}",
            flag_type="STATISTICAL_OUTLIER",
            severity="WARNING",
            title=title,
            plain_explanation=plain_explanation,
            technical_detail=technical_detail,
            evidence=evidence,
            suggestion=suggestion,
            confidence_impact=-10
        )
    
    def _generate_title_from_check(self, check_name: str, note: str) -> str:
        """Generate short human-readable title from check name"""
        title_map = {
            "SUBTOTAL + TAX = TOTAL": "Math Error in Invoice Total",
            "LINE ITEM SUM = SUBTOTAL": "Line Items Don't Add Up",
            "LINE CALCULATIONS": "Incorrect Line Item Math",
            "INVOICE DATE LOGIC": "Impossible Invoice Timeline",
            "INVOICE NUMBER PATTERN": "Suspicious Invoice Number",
            "CURRENCY CONSISTENCY": "Mixed Currencies Detected",
            "TAX RATE SANITY": "Abnormal Tax Rate",
            "ZERO OR NEGATIVE VALUES": "Invalid Zero/Negative Amounts",
            "ROUND NUMBER ANOMALY": "Too Many Round Numbers",
            "FIELD COMPLETENESS": "Missing Required Fields"
        }
        
        # If check_name is in map, use it
        if check_name in title_map:
            return title_map[check_name]
        
        # If contains "LINE" and a number, extract it
        if "LINE" in check_name and any(c.isdigit() for c in check_name):
            import re
            match = re.search(r'LINE (\d+)', check_name)
            if match:
                return f"Math Error on Line {match.group(1)}"
        
        # Default: clean up the check name
        return check_name.replace("_", " ").title()
    
    def _generate_plain_explanation(self, check_name: str, note: str, found_value: Any) -> str:
        """Generate plain English explanation for non-technical users"""
        explanations = {
            "SUBTOTAL + TAX = TOTAL": (
                "The total amount on the invoice does not match the calculated sum of "
                "the subtotal plus tax. This mathematical error suggests either a "
                "calculation mistake or potential manipulation of amounts."
            ),
            "LINE ITEM SUM = SUBTOTAL": (
                "When we add up all the individual line items on this invoice, "
                "the total doesn't match the stated subtotal. This discrepancy "
                "indicates missing charges or calculation errors."
            ),
            "INVOICE DATE LOGIC": (
                "The invoice is dated in the future or the due date is before "
                "the invoice date, which is not possible for a legitimate transaction."
            ),
            "INVOICE NUMBER PATTERN": (
                "The invoice number follows a suspicious auto-incremented pattern "
                "or is missing a company prefix, which may indicate it was generated "
                "automatically without proper vendor identification."
            ),
            "CURRENCY CONSISTENCY": (
                "This invoice contains mixed currency symbols or codes, which is unusual "
                "and may indicate copy-paste errors from multiple sources."
            ),
            "TAX RATE SANITY": (
                "The tax rate on this invoice is outside the normal range of 0-60%, "
                "which is statistically abnormal for any global jurisdiction."
            ),
            "ZERO OR NEGATIVE VALUES": (
                "One or more financial fields contain zero or negative values, "
                "which is invalid unless this is explicitly a credit note or refund."
            ),
            "ROUND NUMBER ANOMALY": (
                "More than 60% of the line item totals are perfectly round numbers "
                "(like 100.00 or 500.00), which is statistically suspicious and "
                "may indicate fabricated data."
            ),
            "FIELD COMPLETENESS": (
                "Required fields such as vendor name, invoice number, or dates "
                "are missing from this invoice, making it incomplete and potentially invalid."
            )
        }
        
        if check_name in explanations:
            return explanations[check_name]
        
        # Default: use the note or a generic explanation
        if note:
            return note
        
        return f"An issue was detected during the {check_name} validation check."
    
    def _generate_technical_detail(self, check_name: str, expected: Any, found: Any, note: str) -> str:
        """Generate precise technical detail with numbers and formulas"""
        details = []
        
        if expected is not None:
            details.append(f"expected_value={expected}")
        if found is not None:
            details.append(f"found_value={found}")
        
        # Add specific technical details based on check type
        if check_name == "SUBTOTAL + TAX = TOTAL":
            if isinstance(found, dict):
                subtotal = found.get('subtotal', 'N/A')
                tax = found.get('tax', 'N/A')
                total = found.get('total', 'N/A')
                details.append(f"Formula: subtotal({subtotal}) + tax({tax}) = expected_total")
        
        elif check_name == "LINE ITEM SUM = SUBTOTAL":
            details.append("Formula: SUM(line_item.line_total) for all items")
        
        elif check_name == "INVOICE DATE LOGIC":
            if isinstance(found, dict):
                inv_date = found.get('invoice_date', 'N/A')
                due_date = found.get('due_date', 'N/A')
                details.append(f"Constraint: due_date({due_date}) >= invoice_date({inv_date})")
        
        elif "LINE" in check_name and "CALCULATION" in check_name:
            details.append("Formula: quantity × unit_price = line_total")
        
        if note:
            details.append(f"note: {note}")
        
        return "; ".join(details) if details else "Technical details not available"
    
    def _generate_suggestion(self, check_name: str, flag_type: str, found_value: Any) -> str:
        """Generate actionable suggestion for human reviewer"""
        suggestions = {
            "MATH_ERROR": "Recalculate all amounts manually and verify against the vendor's original quote or purchase order.",
            "DATE_ANOMALY": "Contact the vendor to confirm the correct invoice date and request a corrected invoice if necessary.",
            "PATTERN_ANOMALY": "Verify the invoice number format against previous invoices from this vendor to ensure consistency.",
            "CURRENCY_ERROR": "Confirm the correct currency with the vendor and check if exchange rate adjustments are needed.",
            "TAX_ANOMALY": "Verify the tax rate against your jurisdiction's tax rules and the vendor's tax registration.",
            "FIELD_MISSING": "Request the vendor provide a complete invoice with all required fields including their full business address."
        }
        
        if flag_type in suggestions:
            return suggestions[flag_type]
        
        return "Review this item carefully and verify against supporting documentation before approving."
    
    def _field_to_plain_name(self, field_name: str) -> str:
        """Convert technical field name to plain English"""
        mapping = {
            'price_z': 'unit price',
            'qty_z': 'quantity',
            'total_z': 'line total'
        }
        return mapping.get(field_name, field_name)
    
    def _generate_line_item_deep_dive(self, result: Dict) -> List[LineItemDeepDive]:
        """Generate deep dive explanations for flagged line items"""
        dives = []
        
        anomalies = result.get('line_item_anomalies', [])
        
        for anomaly in anomalies:
            if not anomaly.get('flagged'):
                continue
            
            line_idx = anomaly.get('line_index', 0)
            description = anomaly.get('description', f'Item {line_idx + 1}')
            unit_price = anomaly.get('unit_price', 0)
            quantity = anomaly.get('quantity', 0)
            line_total = anomaly.get('line_total', 0)
            z_scores = anomaly.get('z_scores', {})
            
            # Calculate invoice averages from z-scores
            # z = (value - mean) / std => mean = value - (z * std)
            # We don't have std, so we'll estimate
            price_z = z_scores.get('price_z', 0)
            
            # Estimate average and deviation
            if price_z != 0:
                invoice_avg = unit_price / (1 + price_z * 0.5)  # Rough estimate
                deviation_factor = unit_price / invoice_avg if invoice_avg > 0 else 1.0
            else:
                invoice_avg = unit_price
                deviation_factor = 1.0
            
            # Generate why_flagged explanation
            if abs(price_z) > 2.5:
                if price_z > 0:
                    why_flagged = (
                        f"The unit price of ₹{unit_price:,.2f} for '{description}' is significantly higher "
                        f"than typical items on this invoice. While the average item costs approximately "
                        f"₹{invoice_avg:,.2f}, this item costs {deviation_factor:.1f}x more — which "
                        f"may warrant verification against standard pricing."
                    )
                else:
                    why_flagged = (
                        f"The unit price of ₹{unit_price:,.2f} for '{description}' is significantly lower "
                        f"than typical items on this invoice. This could indicate a pricing error or "
                        f"potential quality issues with the item."
                    )
            else:
                why_flagged = (
                    f"The combination of price, quantity, and total for '{description}' shows an unusual "
                    f"pattern that doesn't match the statistical distribution of other line items."
                )
            
            # Generate human action
            human_action = (
                f"Verify the market rate for '{description}' and compare against the vendor's "
                f"standard pricing. Check if this is a premium item or if there's a quantity discount applied."
            )
            
            dives.append(LineItemDeepDive(
                line_index=line_idx,
                item_description=description,
                why_flagged=why_flagged,
                key_numbers={
                    "this_item_value": round(unit_price, 2),
                    "invoice_average": round(abs(invoice_avg), 2),
                    "deviation_factor": round(deviation_factor, 1)
                },
                human_action=human_action
            ))
        
        return dives
    
    def _generate_audit_entry(
        self, 
        result: Dict, 
        reasoning_log: List[ReasoningEntry],
        line_dives: List[LineItemDeepDive]
    ) -> AuditEntry:
        """Generate audit trail metadata"""
        
        # Count flags by severity
        critical_count = sum(1 for e in reasoning_log if e.severity == "CRITICAL")
        warning_count = sum(1 for e in reasoning_log if e.severity == "WARNING")
        info_count = sum(1 for e in reasoning_log if e.severity == "INFO")
        
        # Get top 3 risk factors
        top_risks = []
        for entry in reasoning_log[:3]:
            top_risks.append(f"[{entry.severity}] {entry.title}")
        
        # Get counts
        rules_checks = result.get('rules_checks', [])
        line_anomalies = result.get('line_item_anomalies', [])
        
        # Calculate hash of reasoning log
        reasoning_str = json.dumps([self._entry_to_dict(e) for e in reasoning_log], sort_keys=True)
        hash_value = hashlib.md5(reasoning_str.encode()).hexdigest()
        
        verdict = result.get('verdict', 'UNKNOWN')
        confidence = result.get('final_confidence_score', 0)
        
        return AuditEntry(
            analysis_timestamp=datetime.utcnow().isoformat(),
            engine_version=self.VERSION,
            total_flags_raised=len(reasoning_log),
            critical_flags=critical_count,
            warning_flags=warning_count,
            info_flags=info_count,
            rules_checks_run=len(rules_checks),
            line_items_analyzed=len(line_anomalies),
            anomalous_line_items=len(line_dives),
            final_verdict=verdict,
            confidence_score=confidence,
            score_breakdown={
                "rule_engine_score": result.get('rule_score', 0),
                "ml_anomaly_score": result.get('ml_score', 0),
                "weighted_final": confidence
            },
            top_risk_factors=top_risks,
            reviewer_action_required=verdict != "LIKELY GENUINE",
            exported_by="XAI Reasoning Engine",
            chain_of_reasoning_hash=hash_value
        )
    
    # Helper methods for serialization
    def _entry_to_dict(self, entry: ReasoningEntry) -> Dict:
        return {
            "flag_id": entry.flag_id,
            "flag_type": entry.flag_type,
            "severity": entry.severity,
            "title": entry.title,
            "plain_explanation": entry.plain_explanation,
            "technical_detail": entry.technical_detail,
            "evidence": entry.evidence,
            "suggestion": entry.suggestion,
            "confidence_impact": entry.confidence_impact
        }
    
    def _dive_to_dict(self, dive: LineItemDeepDive) -> Dict:
        return {
            "line_index": dive.line_index,
            "item_description": dive.item_description,
            "why_flagged": dive.why_flagged,
            "key_numbers": dive.key_numbers,
            "human_action": dive.human_action
        }
    
    def _audit_to_dict(self, audit: AuditEntry) -> Dict:
        return {
            "analysis_timestamp": audit.analysis_timestamp,
            "engine_version": audit.engine_version,
            "total_flags_raised": audit.total_flags_raised,
            "critical_flags": audit.critical_flags,
            "warning_flags": audit.warning_flags,
            "info_flags": audit.info_flags,
            "rules_checks_run": audit.rules_checks_run,
            "line_items_analyzed": audit.line_items_analyzed,
            "anomalous_line_items": audit.anomalous_line_items,
            "final_verdict": audit.final_verdict,
            "confidence_score": audit.confidence_score,
            "score_breakdown": audit.score_breakdown,
            "top_risk_factors": audit.top_risk_factors,
            "reviewer_action_required": audit.reviewer_action_required,
            "exported_by": audit.exported_by,
            "chain_of_reasoning_hash": audit.chain_of_reasoning_hash
        }


# Singleton instance
_xai_engine = None

def get_xai_reasoning_engine() -> XAIReasoningEngine:
    """Get or create singleton XAI reasoning engine"""
    global _xai_engine
    if _xai_engine is None:
        _xai_engine = XAIReasoningEngine()
    return _xai_engine
