"""
Forgery Detection Engine - Two-Stage Hybrid Analysis Pipeline
Stage 1: Deterministic Rules Engine
Stage 2: Statistical Anomaly Detection (Isolation Forest Logic)
"""
import numpy as np
from typing import Dict, Any, List, Optional, Tuple
from dataclasses import dataclass, field
from datetime import datetime
from statistics import mean, stdev
import re


@dataclass
class RuleCheck:
    """Single rule check result"""
    check_name: str
    passed: bool
    expected_value: Any
    found_value: Any
    severity: str  # "critical", "warning", "info"
    note: str


@dataclass
class LineItemAnomaly:
    """Anomaly detection result for a line item"""
    line_index: int
    description: str
    unit_price: float
    quantity: float
    line_total: float
    anomaly_score: float
    z_scores: Dict[str, float]
    flagged: bool


@dataclass
class DetectionResult:
    """Complete forgery detection result"""
    verdict: str
    final_confidence_score: float
    rule_score: float
    ml_score: float
    rules_checks: List[Dict]
    line_item_anomalies: List[Dict]
    summary_flags: List[str]
    recommended_action: str
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "verdict": self.verdict,
            "final_confidence_score": round(self.final_confidence_score, 2),
            "rule_score": round(self.rule_score, 2),
            "ml_score": round(self.ml_score, 2),
            "rules_checks": self.rules_checks,
            "line_item_anomalies": self.line_item_anomalies,
            "summary_flags": self.summary_flags,
            "recommended_action": self.recommended_action
        }


class ForgeryDetectionService:
    """
    Two-stage hybrid analysis pipeline for invoice forgery detection
    """
    
    def __init__(self):
        # Reduced penalties to prevent unnecessary human verification
        self.critical_penalty = 15  # Was 25
        self.warning_penalty = 5    # Was 10
        self.info_penalty = 1     # Was 3
        
    def analyze(self, invoice_data: Dict[str, Any]) -> DetectionResult:
        """
        Run complete two-stage analysis on invoice data
        """
        # Stage 1: Deterministic Rules
        rule_checks = self._run_deterministic_rules(invoice_data)
        rule_score = self._calculate_rule_score(rule_checks)
        
        # Stage 2: Statistical Anomaly Detection
        line_anomalies = self._detect_statistical_anomalies(invoice_data)
        ml_score = self._calculate_ml_score(line_anomalies)
        
        # Stage 3: Final Verdict
        final_score = (0.6 * rule_score) + (0.4 * ml_score)
        verdict = self._determine_verdict(final_score)
        summary_flags = self._generate_summary_flags(rule_checks, line_anomalies)
        recommended_action = self._get_recommended_action(verdict, summary_flags)
        
        return DetectionResult(
            verdict=verdict,
            final_confidence_score=final_score,
            rule_score=rule_score,
            ml_score=ml_score,
            rules_checks=[self._check_to_dict(c) for c in rule_checks],
            line_item_anomalies=[self._anomaly_to_dict(a) for a in line_anomalies],
            summary_flags=summary_flags,
            recommended_action=recommended_action
        )
    
    def _run_deterministic_rules(self, data: Dict) -> List[RuleCheck]:
        """Run all 10 deterministic rule checks"""
        checks = []
        
        # Extract values
        subtotal = self._to_float(data.get('subtotal'))
        tax = self._to_float(data.get('tax'))
        tax_rate = self._to_float(data.get('tax_rate'))
        total = self._to_float(data.get('total'))
        line_items = data.get('line_items', [])
        invoice_date = data.get('invoice_date')
        due_date = data.get('due_date')
        invoice_number = data.get('invoice_number')
        vendor_name = data.get('vendor_name')
        vendor_address = data.get('vendor_address')
        buyer_name = data.get('buyer_name')
        currency = data.get('currency', '')
        
        # Check 1: SUBTOTAL + TAX = TOTAL
        checks.append(self._check_math_total(subtotal, tax, tax_rate, total))
        
        # Check 2: LINE ITEM SUM = SUBTOTAL
        checks.append(self._check_line_item_sum(line_items, subtotal))
        
        # Check 3: QUANTITY * UNIT PRICE = LINE TOTAL (per line)
        checks.extend(self._check_line_calculations(line_items))
        
        # Check 4: INVOICE DATE LOGIC
        checks.append(self._check_date_logic(invoice_date, due_date))
        
        # Check 5: DUPLICATE INVOICE NUMBER
        checks.append(self._check_invoice_number_pattern(invoice_number))
        
        # Check 6: CURRENCY CONSISTENCY
        checks.append(self._check_currency_consistency(line_items, currency))
        
        # Check 7: TAX RATE SANITY CHECK
        checks.append(self._check_tax_rate_sanity(tax_rate))
        
        # Check 8: ZERO OR NEGATIVE VALUES
        checks.append(self._check_zero_negative_values(line_items, subtotal, tax, total))
        
        # Check 9: ROUND NUMBER ANOMALY
        checks.append(self._check_round_number_anomaly(line_items))
        
        # Check 10: VENDOR/BUYER FIELD COMPLETENESS
        checks.append(self._check_field_completeness(
            vendor_name, vendor_address, buyer_name, 
            invoice_number, invoice_date, total
        ))
        
        return checks
    
    def _check_math_total(self, subtotal: Optional[float], tax: Optional[float], 
                          tax_rate: Optional[float], total: Optional[float]) -> RuleCheck:
        """Check 1: SUBTOTAL + TAX = TOTAL"""
        if subtotal is None or total is None:
            return RuleCheck(
                check_name="SUBTOTAL + TAX = TOTAL",
                passed=False,
                expected_value=None,
                found_value={"subtotal": subtotal, "tax": tax, "total": total},
                severity="critical",
                note="Missing required financial fields for math validation"
            )
        
        # Calculate expected total
        if tax is not None:
            expected_total = subtotal + tax
        elif tax_rate is not None:
            expected_total = subtotal + (subtotal * tax_rate)
        else:
            expected_total = subtotal
        
        diff = abs(expected_total - total)
        passed = diff <= 0.01
        
        return RuleCheck(
            check_name="SUBTOTAL + TAX = TOTAL",
            passed=passed,
            expected_value=round(expected_total, 2),
            found_value=round(total, 2),
            severity="critical" if not passed else "info",
            note=f"Math check {'passed' if passed else f'failed: difference={round(diff, 2)}'}"
        )
    
    def _check_line_item_sum(self, line_items: List[Dict], subtotal: Optional[float]) -> RuleCheck:
        """Check 2: LINE ITEM SUM = SUBTOTAL"""
        if not line_items or subtotal is None:
            return RuleCheck(
                check_name="LINE ITEM SUM = SUBTOTAL",
                passed=True,  # Skip if no line items
                expected_value=None,
                found_value=None,
                severity="info",
                note="No line items to validate"
            )
        
        calculated_subtotal = sum(
            self._to_float(item.get('line_total', 0)) for item in line_items
        )
        diff = abs(calculated_subtotal - subtotal)
        passed = diff <= 0.01
        
        return RuleCheck(
            check_name="LINE ITEM SUM = SUBTOTAL",
            passed=passed,
            expected_value=round(calculated_subtotal, 2),
            found_value=round(subtotal, 2),
            severity="critical" if not passed else "info",
            note=f"Line sum {'matches' if passed else f'mismatch: diff={round(diff, 2)}'} subtotal"
        )
    
    def _check_line_calculations(self, line_items: List[Dict]) -> List[RuleCheck]:
        """Check 3: QUANTITY * UNIT PRICE = LINE TOTAL per line"""
        checks = []
        
        if not line_items:
            return [RuleCheck(
                check_name="LINE CALCULATIONS",
                passed=True,
                expected_value=None,
                found_value=None,
                severity="info",
                note="No line items to validate"
            )]
        
        for i, item in enumerate(line_items):
            qty = self._to_float(item.get('quantity'))
            unit_price = self._to_float(item.get('unit_price'))
            line_total = self._to_float(item.get('line_total'))
            
            if qty is None or unit_price is None or line_total is None:
                checks.append(RuleCheck(
                    check_name=f"LINE {i+1} CALCULATION",
                    passed=False,
                    expected_value=None,
                    found_value={"qty": qty, "unit_price": unit_price, "line_total": line_total},
                    severity="warning",
                    note="Missing fields for line calculation"
                ))
                continue
            
            expected_total = qty * unit_price
            diff = abs(expected_total - line_total)
            passed = diff <= 0.01
            
            checks.append(RuleCheck(
                check_name=f"LINE {i+1}: QTY * PRICE = TOTAL",
                passed=passed,
                expected_value=round(expected_total, 2),
                found_value=round(line_total, 2),
                severity="warning" if not passed else "info",
                note=f"Line {i+1} calculation {'correct' if passed else f'incorrect: diff={round(diff, 2)}'}"
            ))
        
        return checks
    
    def _check_date_logic(self, invoice_date: Any, due_date: Any) -> RuleCheck:
        """Check 4: INVOICE DATE LOGIC"""
        if not invoice_date or not due_date:
            return RuleCheck(
                check_name="INVOICE DATE LOGIC",
                passed=True,  # Skip if missing
                expected_value=None,
                found_value={"invoice_date": invoice_date, "due_date": due_date},
                severity="info",
                note="Missing dates for validation"
            )
        
        try:
            inv_date = self._parse_date(invoice_date)
            due = self._parse_date(due_date)
            
            if inv_date and due:
                passed = due >= inv_date
                return RuleCheck(
                    check_name="INVOICE DATE LOGIC",
                    passed=passed,
                    expected_value=f"due_date >= invoice_date",
                    found_value=f"invoice={invoice_date}, due={due_date}",
                    severity="critical" if not passed else "info",
                    note="Due date is before invoice date (impossible timeline)" if not passed else "Date logic valid"
                )
        except:
            pass
        
        return RuleCheck(
            check_name="INVOICE DATE LOGIC",
            passed=True,
            expected_value=None,
            found_value={"invoice_date": invoice_date, "due_date": due_date},
            severity="info",
            note="Could not parse dates for validation"
        )
    
    def _check_invoice_number_pattern(self, invoice_number: Optional[str]) -> RuleCheck:
        """Check 5: DUPLICATE INVOICE NUMBER / SUSPICIOUS PATTERN"""
        if not invoice_number:
            return RuleCheck(
                check_name="INVOICE NUMBER PATTERN",
                passed=False,
                expected_value="Valid invoice number",
                found_value=None,
                severity="warning",
                note="Missing invoice number"
            )
        
        # Check for suspicious patterns
        suspicious_patterns = [
            r'^0+$',  # All zeros
            r'^INV-0{3,}\d+$',  # INV-0001 pattern (auto-incremented with padding)
            r'^\d{1,4}$',  # Pure sequential integers without prefix
        ]
        
        is_suspicious = any(re.match(pattern, invoice_number, re.IGNORECASE) 
                           for pattern in suspicious_patterns)
        
        # Check for missing company prefix (simple heuristic)
        has_prefix = bool(re.match(r'^[A-Z]{2,}', invoice_number, re.IGNORECASE))
        
        passed = not is_suspicious and has_prefix
        
        note_parts = []
        if is_suspicious:
            note_parts.append("Suspicious auto-incremented pattern detected")
        if not has_prefix:
            note_parts.append("Missing company prefix")
        
        return RuleCheck(
            check_name="INVOICE NUMBER PATTERN",
            passed=passed,
            expected_value="Invoice number with company prefix",
            found_value=invoice_number,
            severity="warning" if not passed else "info",
            note="; ".join(note_parts) if note_parts else "Invoice number pattern looks valid"
        )
    
    def _check_currency_consistency(self, line_items: List[Dict], currency: str) -> RuleCheck:
        """Check 6: CURRENCY CONSISTENCY"""
        currencies_found = set()
        
        # Check main currency
        if currency:
            currencies_found.add(currency.upper())
        
        # Check line items for currency symbols
        currency_pattern = r'[$€£¥]'
        for item in line_items:
            for field in ['unit_price', 'line_total', 'description']:
                val = str(item.get(field, ''))
                matches = re.findall(currency_pattern, val)
                currencies_found.update(matches)
        
        passed = len(currencies_found) <= 1
        
        return RuleCheck(
            check_name="CURRENCY CONSISTENCY",
            passed=passed,
            expected_value="Single currency throughout",
            found_value=list(currencies_found),
            severity="warning" if not passed else "info",
            note=f"{'Mixed currencies detected' if not passed else 'Currency consistent'}: {currencies_found}"
        )
    
    def _check_tax_rate_sanity(self, tax_rate: Optional[float]) -> RuleCheck:
        """Check 7: TAX RATE SANITY CHECK"""
        if tax_rate is None:
            return RuleCheck(
                check_name="TAX RATE SANITY",
                passed=True,
                expected_value=None,
                found_value=None,
                severity="info",
                note="No tax rate to validate"
            )
        
        # Convert percentage to decimal if needed
        rate = tax_rate
        if rate > 1:
            rate = rate / 100
        
        passed = 0 <= rate <= 0.60
        
        return RuleCheck(
            check_name="TAX RATE SANITY",
            passed=passed,
            expected_value="0% - 60%",
            found_value=f"{round(rate * 100, 2)}%",
            severity="critical" if not passed else "info",
            note=f"Tax rate {round(rate * 100, 2)}% is {'abnormal' if not passed else 'within normal range'}"
        )
    
    def _check_zero_negative_values(self, line_items: List[Dict], 
                                    subtotal: Optional[float], 
                                    tax: Optional[float], 
                                    total: Optional[float]) -> RuleCheck:
        """Check 8: ZERO OR NEGATIVE VALUES"""
        issues = []
        
        # Check line items
        for i, item in enumerate(line_items):
            qty = self._to_float(item.get('quantity'))
            unit_price = self._to_float(item.get('unit_price'))
            line_total = self._to_float(item.get('line_total'))
            
            if qty is not None and qty <= 0:
                issues.append(f"Line {i+1}: zero/negative quantity ({qty})")
            if unit_price is not None and unit_price <= 0:
                issues.append(f"Line {i+1}: zero/negative unit price ({unit_price})")
            if line_total is not None and line_total <= 0:
                # Allow if it's explicitly a discount/credit
                desc = str(item.get('description', '')).lower()
                if 'discount' not in desc and 'credit' not in desc:
                    issues.append(f"Line {i+1}: zero/negative line total ({line_total})")
        
        # Check totals
        if subtotal is not None and subtotal <= 0:
            issues.append(f"Zero/negative subtotal ({subtotal})")
        if tax is not None and tax < 0:
            issues.append(f"Negative tax ({tax})")
        if total is not None and total <= 0:
            issues.append(f"Zero/negative total ({total})")
        
        passed = len(issues) == 0
        
        return RuleCheck(
            check_name="ZERO OR NEGATIVE VALUES",
            passed=passed,
            expected_value="All positive values",
            found_value=issues if issues else "All values positive",
            severity="critical" if not passed else "info",
            note="; ".join(issues) if issues else "No zero or negative values found"
        )
    
    def _check_round_number_anomaly(self, line_items: List[Dict]) -> RuleCheck:
        """Check 9: ROUND NUMBER ANOMALY"""
        if not line_items:
            return RuleCheck(
                check_name="ROUND NUMBER ANOMALY",
                passed=True,
                expected_value=None,
                found_value=None,
                severity="info",
                note="No line items to analyze"
            )
        
        round_count = 0
        total_items = 0
        
        for item in line_items:
            line_total = self._to_float(item.get('line_total'))
            if line_total is not None:
                total_items += 1
                # Check if perfectly round (e.g., 100.00, 500.00)
                if line_total > 0 and line_total == round(line_total):
                    round_count += 1
        
        if total_items == 0:
            return RuleCheck(
                check_name="ROUND NUMBER ANOMALY",
                passed=True,
                expected_value=None,
                found_value=None,
                severity="info",
                note="No valid line totals to analyze"
            )
        
        round_percentage = (round_count / total_items) * 100
        passed = round_percentage < 60
        
        return RuleCheck(
            check_name="ROUND NUMBER ANOMALY",
            passed=passed,
            expected_value="< 60% round numbers",
            found_value=f"{round(round_percentage, 1)}% round ({round_count}/{total_items})",
            severity="warning" if not passed else "info",
            note=f"{round(round_percentage, 1)}% of line totals are perfectly round numbers"
        )
    
    def _check_field_completeness(self, vendor_name: Optional[str], 
                                   vendor_address: Optional[str],
                                   buyer_name: Optional[str],
                                   invoice_number: Optional[str],
                                   invoice_date: Any,
                                   total: Optional[float]) -> RuleCheck:
        """Check 10: VENDOR/BUYER FIELD COMPLETENESS"""
        missing = []
        
        if not vendor_name:
            missing.append("vendor name")
        if not vendor_address:
            missing.append("vendor address")
        if not buyer_name:
            missing.append("buyer name")
        if not invoice_number:
            missing.append("invoice number")
        if not invoice_date:
            missing.append("invoice date")
        if total is None:
            missing.append("total amount")
        
        passed = len(missing) == 0
        
        return RuleCheck(
            check_name="FIELD COMPLETENESS",
            passed=passed,
            expected_value="All required fields present",
            found_value=f"Missing: {', '.join(missing)}" if missing else "All fields present",
            severity="warning" if missing else "info",
            note=f"Missing fields: {', '.join(missing)}" if missing else "All required fields found"
        )
    
    def _detect_statistical_anomalies(self, data: Dict) -> List[LineItemAnomaly]:
        """Stage 2: Statistical Anomaly Detection using Isolation Forest logic"""
        line_items = data.get('line_items', [])
        
        if not line_items:
            return []
        
        # Extract numeric features
        features = []
        for item in line_items:
            unit_price = self._to_float(item.get('unit_price'))
            quantity = self._to_float(item.get('quantity'))
            line_total = self._to_float(item.get('line_total'))
            discount = self._to_float(item.get('discount_percent', 0))
            
            # Skip invalid items
            if unit_price is None or quantity is None or line_total is None:
                continue
                
            features.append({
                'unit_price': unit_price,
                'quantity': quantity,
                'line_total': line_total,
                'discount': discount
            })
        
        if len(features) < 2:
            return []  # Need at least 2 items for statistics
        
        # Calculate statistics
        prices = [f['unit_price'] for f in features]
        quantities = [f['quantity'] for f in features]
        totals = [f['line_total'] for f in features]
        
        price_mean, price_std = self._calc_mean_std(prices)
        qty_mean, qty_std = self._calc_mean_std(quantities)
        total_mean, total_std = self._calc_mean_std(totals)
        
        # Detect anomalies
        anomalies = []
        for i, (item, feat) in enumerate(zip(line_items, features)):
            # Calculate z-scores
            price_z = self._calc_zscore(feat['unit_price'], price_mean, price_std)
            qty_z = self._calc_zscore(feat['quantity'], qty_mean, qty_std)
            total_z = self._calc_zscore(feat['line_total'], total_mean, total_std)
            
            # Calculate anomaly score
            anomaly_score = self._calc_anomaly_score(price_z, qty_z, total_z)
            
            # Check discount anomaly
            discount_flag = feat['discount'] > 50
            
            # Flag if z-score > 2.5 or anomaly score > 0.6
            flagged = abs(price_z) > 2.5 or abs(qty_z) > 2.5 or abs(total_z) > 2.5 or anomaly_score > 0.6
            
            desc = item.get('description', f'Line {i+1}')
            
            anomalies.append(LineItemAnomaly(
                line_index=i,
                description=desc,
                unit_price=feat['unit_price'],
                quantity=feat['quantity'],
                line_total=feat['line_total'],
                anomaly_score=anomaly_score,
                z_scores={
                    'price_z': round(price_z, 3),
                    'qty_z': round(qty_z, 3),
                    'total_z': round(total_z, 3)
                },
                flagged=flagged
            ))
        
        return anomalies
    
    def _calc_mean_std(self, values: List[float]) -> Tuple[float, float]:
        """Calculate mean and standard deviation"""
        if len(values) < 2:
            return values[0] if values else 0, 0
        
        m = mean(values)
        try:
            s = stdev(values)
        except:
            s = 0
        
        return m, s
    
    def _calc_zscore(self, value: float, mean: float, std: float) -> float:
        """Calculate z-score"""
        if std == 0:
            return 0
        return (value - mean) / std
    
    def _calc_anomaly_score(self, price_z: float, qty_z: float, total_z: float) -> float:
        """Calculate weighted anomaly score (0-1)"""
        # Normalize z-scores (clip to reasonable range)
        price_norm = min(abs(price_z) / 3, 1.0)  # Max at 3 std devs
        qty_norm = min(abs(qty_z) / 3, 1.0)
        total_norm = min(abs(total_z) / 3, 1.0)
        
        # Weighted average
        score = (0.4 * price_norm) + (0.3 * qty_norm) + (0.3 * total_norm)
        
        return round(min(score, 1.0), 3)
    
    def _calculate_rule_score(self, checks: List[RuleCheck]) -> float:
        """Calculate rule score (0-100)"""
        score = 100
        
        for check in checks:
            if not check.passed:
                if check.severity == "critical":
                    score -= self.critical_penalty
                elif check.severity == "warning":
                    score -= self.warning_penalty
                elif check.severity == "info":
                    score -= self.info_penalty
        
        return max(0, score)
    
    def _calculate_ml_score(self, anomalies: List[LineItemAnomaly]) -> float:
        """Calculate ML score (0-100) based on anomaly scores"""
        if not anomalies:
            return 100  # No anomalies = perfect score
        
        avg_anomaly = mean([a.anomaly_score for a in anomalies])
        ml_score = (1 - avg_anomaly) * 100
        
        return round(ml_score, 2)
    
    def _determine_verdict(self, final_score: float) -> str:
        """Determine final verdict based on confidence score"""
        if final_score >= 85:  # Was 80
            return "LIKELY GENUINE"
        elif final_score >= 40:  # Was 50 - more lenient threshold
            return "SUSPICIOUS - REVIEW REQUIRED"
        else:
            return "HIGH FORGERY RISK"
    
    def _generate_summary_flags(self, checks: List[RuleCheck], 
                                 anomalies: List[LineItemAnomaly]) -> List[str]:
        """Generate summary flags"""
        flags = []
        
        # Rule-based flags
        critical_failures = [c for c in checks if not c.passed and c.severity == "critical"]
        if critical_failures:
            flags.append(f"{len(critical_failures)} critical rule failures")
        
        warning_failures = [c for c in checks if not c.passed and c.severity == "warning"]
        if warning_failures:
            flags.append(f"{len(warning_failures)} warning flags")
        
        # Anomaly flags
        flagged_items = [a for a in anomalies if a.flagged]
        if flagged_items:
            flags.append(f"{len(flagged_items)} line items statistically anomalous")
        
        if not flags:
            flags.append("No significant flags detected")
        
        return flags
    
    def _get_recommended_action(self, verdict: str, flags: List[str]) -> str:
        """Generate recommended action"""
        if verdict == "LIKELY GENUINE":
            return "Proceed with standard processing"
        elif verdict == "SUSPICIOUS - REVIEW REQUIRED":
            return "Manual review recommended before payment approval"
        else:
            return "STOP - Do not process payment without thorough investigation"
    
    def _to_float(self, value: Any) -> Optional[float]:
        """Safely convert value to float"""
        if value is None:
            return None
        try:
            # Remove currency symbols and commas
            if isinstance(value, str):
                value = re.sub(r'[$€£¥,\s]', '', value)
            return float(value)
        except (ValueError, TypeError):
            return None
    
    def _parse_date(self, date_value: Any) -> Optional[datetime]:
        """Parse date from various formats"""
        if not date_value:
            return None
        
        formats = [
            "%Y-%m-%d",
            "%d/%m/%Y",
            "%m/%d/%Y",
            "%d-%m-%Y",
            "%m-%d-%Y",
            "%d %b %Y",
            "%d %B %Y",
            "%b %d, %Y",
            "%B %d, %Y"
        ]
        
        for fmt in formats:
            try:
                return datetime.strptime(str(date_value), fmt)
            except:
                continue
        
        return None
    
    def _check_to_dict(self, check: RuleCheck) -> Dict:
        """Convert RuleCheck to dict"""
        return {
            "check_name": check.check_name,
            "passed": check.passed,
            "expected_value": check.expected_value,
            "found_value": check.found_value,
            "severity": check.severity,
            "note": check.note
        }
    
    def _anomaly_to_dict(self, anomaly: LineItemAnomaly) -> Dict:
        """Convert LineItemAnomaly to dict"""
        return {
            "line_index": anomaly.line_index,
            "description": anomaly.description,
            "unit_price": anomaly.unit_price,
            "quantity": anomaly.quantity,
            "line_total": anomaly.line_total,
            "anomaly_score": anomaly.anomaly_score,
            "z_scores": anomaly.z_scores,
            "flagged": anomaly.flagged
        }


# Singleton instance
_detection_service = None

def get_forgery_detection_service() -> ForgeryDetectionService:
    """Get or create singleton detection service"""
    global _detection_service
    if _detection_service is None:
        _detection_service = ForgeryDetectionService()
    return _detection_service
