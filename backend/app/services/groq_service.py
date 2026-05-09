from groq import Groq
from app.core.config import settings
from typing import Dict, List, Any

class GroqService:
    def __init__(self):
        self.client = Groq(api_key=settings.groq_api_key) if settings.groq_api_key else None
        self.model = "llama-3.3-70b-versatile"
    
    def analyze_invoice(self, invoice_data: dict) -> dict:
        """
        Analyze invoice for fraud indicators using Groq AI.
        Returns detailed reasoning with risk factors.
        """
        if not self.client:
            return {
                'success': False,
                'reasoning': 'AI analysis unavailable: Groq API key not configured',
                'risk_factors': [],
                'confidence': 50
            }
        
        try:
            prompt = self._build_analysis_prompt(invoice_data)
            
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {
                        "role": "system",
                        "content": "You are an expert invoice fraud detection analyst. Analyze the provided invoice data and identify potential fraud indicators, anomalies, and risk factors. Provide detailed, specific findings with evidence from the data. Be accurate about tax rates for different product categories."
                    },
                    {
                        "role": "user",
                        "content": prompt
                    }
                ],
                temperature=0.3,
                max_tokens=1500
            )
            
            reasoning = response.choices[0].message.content
            
            return {
                'success': True,
                'reasoning': reasoning,
                'risk_factors': self._extract_risk_factors(reasoning),
                'confidence': self._calculate_confidence(reasoning)
            }
            
        except Exception as e:
            return {
                'success': False,
                'reasoning': f"AI analysis temporarily unavailable. Invoice data extracted successfully.",
                'risk_factors': [],
                'confidence': 50,
                'error': str(e)
            }
    
    def _build_analysis_prompt(self, invoice_data: dict) -> str:
        """Build comprehensive analysis prompt with category context"""
        
        category = self._detect_category(invoice_data)
        expected_tax_rate = self._get_expected_tax_rate(category)
        
        prompt = f"""Analyze this invoice for fraud indicators:

**VENDOR INFORMATION:**
- Name: {invoice_data.get('vendor_name', 'N/A')}
- Address: {invoice_data.get('vendor_address', 'N/A')}
- Phone: {invoice_data.get('vendor_phone', 'N/A')}
- GSTIN: {invoice_data.get('gstin', 'N/A')}

**INVOICE DETAILS:**
- Invoice #: {invoice_data.get('invoice_number', 'N/A')}
- Date: {invoice_data.get('invoice_date', 'N/A')}
- Payment: {invoice_data.get('payment_method', 'N/A')}

**FINANCIAL DATA:**
- Subtotal: ₹{invoice_data.get('subtotal', 0)}
- Tax: ₹{invoice_data.get('tax', 0)}
- Total: ₹{invoice_data.get('total', 0)}

**LINE ITEMS:**
"""
        for i, item in enumerate(invoice_data.get('line_items', []), 1):
            prompt += f"{i}. {item.get('description', '')}: {item.get('quantity', 0)} × ₹{item.get('unit_price', 0)} = ₹{item.get('amount', 0)}\n"
        
        prompt += f"""
**PRODUCT CATEGORY:** {category}
**EXPECTED TAX RATE:** {expected_tax_rate}

**VALIDATION CHECKS TO PERFORM:**

1. **Mathematical Consistency:**
   - Verify: Qty × Unit Price = Amount for each line item
   - Verify: Sum of all line items = Subtotal
   - Verify: Subtotal + Tax = Total
   - Allow ±₹1.0 tolerance for rounding differences

2. **Date Validation:**
   - Check if date is in future (potential fraud)
   - Check if date is unusually old (>1 year)
   - Verify date format is valid

3. **Tax Rate Analysis:**
   - Compare actual tax rate with expected rate for {category}
   - Flag if tax rate is significantly different from expected
   - Note: LPG/Gas has 5% GST, not 18%

4. **Line Item Anomalies:**
   - Unusually round numbers
   - Duplicate items
   - Missing quantities or prices
   - Suspicious descriptions

5. **Vendor Risk:**
   - Missing contact information
   - Invalid GSTIN format
   - Unknown vendor

6. **Payment Method:**
   - Cash payments over ₹10,000 (suspicious)
   - Missing payment method

**OUTPUT FORMAT:**
Provide specific findings with evidence. Example:
- ✅ Math validation: All calculations correct (861.90 + 21.55 + 21.55 = 905.00)
- ⚠️ Date anomaly: Invoice dated 6 months in future
- ✅ Tax rate: 5% CGST + 5% SGST is correct for LPG cylinder
- ❌ Missing: Vendor phone number not found

Be specific, accurate, and evidence-based."""
        
        return prompt
    
    def _detect_category(self, invoice_data: dict) -> str:
        """Detect product category from line items"""
        line_items = invoice_data.get('line_items', [])
        descriptions = ' '.join(item.get('description', '').lower() for item in line_items)
        
        if 'gas' in descriptions or 'cylinder' in descriptions or 'lpg' in descriptions:
            return 'LPG Gas Cylinder'
        elif 'food' in descriptions or 'restaurant' in descriptions:
            return 'Food & Beverage'
        elif 'electronics' in descriptions or 'mobile' in descriptions:
            return 'Electronics'
        elif 'medicine' in descriptions or 'pharma' in descriptions:
            return 'Pharmaceuticals'
        else:
            return 'General Retail'
    
    def _get_expected_tax_rate(self, category: str) -> str:
        """Get expected tax rate for category"""
        rates = {
            'LPG Gas Cylinder': '5% GST (2.5% CGST + 2.5% SGST)',
            'Food & Beverage': '5% or 18% GST depending on type',
            'Electronics': '18% or 28% GST',
            'Pharmaceuticals': '12% or 18% GST',
            'General Retail': '18% GST',
        }
        return rates.get(category, '18% GST')
    
    def _extract_risk_factors(self, reasoning: str) -> list:
        """Extract risk factors from AI reasoning"""
        risk_keywords = ['fraud', 'suspicious', 'anomaly', 'risk', 'unusual', 'concern', 'warning', 'missing', 'failed']
        factors = []
        for line in reasoning.split('\n'):
            line = line.strip()
            if line and any(keyword in line.lower() for keyword in risk_keywords):
                if line.startswith('❌') or line.startswith('⚠️'):
                    factors.append(line)
        return factors[:5]
    
    def _calculate_confidence(self, reasoning: str) -> int:
        """Calculate confidence score based on reasoning quality"""
        if not reasoning or 'unavailable' in reasoning.lower():
            return 50
        word_count = len(reasoning.split())
        if word_count > 300:
            return 95
        elif word_count > 150:
            return 85
        elif word_count > 80:
            return 70
        else:
            return 60
