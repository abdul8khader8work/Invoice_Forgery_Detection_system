"""
LLM-based Invoice Extraction
Uses multiple API providers (Groq, OpenRouter, HuggingFace) to extract structured data from OCR text
"""

import logging
import re
import os
from typing import Dict, List, Any, Optional
from pathlib import Path

logger = logging.getLogger(__name__)


class LLMInvoiceExtractor:
    """
    Extract invoice data using LLM from OCR text with multi-provider support
    Supports: Groq, OpenRouter, HuggingFace
    Much better than regex - understands context
    """
    
    def __init__(self, api_key: Optional[str] = None):
        """
        Initialize with multiple API providers
        
        Providers tried in order: Groq -> OpenRouter -> HuggingFace -> regex fallback
        """
        # Provider configurations
        self.providers = []
        
        # Groq provider (primary)
        groq_keys = os.getenv('GROQ_API_KEY', '').split(',')
        groq_keys = [k.strip() for k in groq_keys if k.strip()]
        if groq_keys:
            self.providers.append({
                'name': 'Groq',
                'base_url': 'https://api.groq.com/openai/v1',
                'model': 'llama-3.3-70b-versatile',
                'keys': groq_keys,
                'current_key_index': 0,
                'type': 'openai_compatible'
            })
            logger.info(f"Added Groq provider with {len(groq_keys)} key(s)")
        
        # OpenRouter provider
        openrouter_key = os.getenv('OPENROUTER_API_KEY', '').strip()
        if openrouter_key:
            self.providers.append({
                'name': 'OpenRouter',
                'base_url': 'https://openrouter.ai/api/v1',
                'model': 'meta-llama/llama-3.3-70b-instruct:free',
                'keys': [openrouter_key],
                'current_key_index': 0,
                'type': 'openai_compatible'
            })
            logger.info("Added OpenRouter provider")
        
        # HuggingFace provider
        huggingface_key = os.getenv('HUGGINGFACE_API_KEY', '').strip()
        if huggingface_key:
            self.providers.append({
                'name': 'HuggingFace',
                'base_url': 'https://api-inference.huggingface.co/models/mistralai/Mistral-7B-Instruct-v0.2',
                'model': 'mistralai/Mistral-7B-Instruct-v0.2',
                'keys': [huggingface_key],
                'current_key_index': 0,
                'type': 'huggingface'
            })
            logger.info("Added HuggingFace provider")
        
        # Track current provider and key
        self.current_provider_index = 0
        
        # Set initial key for backward compatibility
        if self.providers:
            self.api_key = self.providers[0]['keys'][0]
            self.base_url = self.providers[0]['base_url']
            logger.info(f"Initialized with {len(self.providers)} provider(s)")
        else:
            logger.warning("No API providers configured. Will use regex fallback only.")
            self.api_key = None
            self.base_url = None
    
    def _rotate_api_key(self):
        """Rotate to the next available API key within current provider"""
        if not self.providers:
            return False
        
        provider = self.providers[self.current_provider_index]
        if len(provider['keys']) <= 1:
            return False  # No rotation possible within provider
        
        provider['current_key_index'] = (provider['current_key_index'] + 1) % len(provider['keys'])
        self.api_key = provider['keys'][provider['current_key_index']]
        logger.info(f"Rotated to API key {provider['current_key_index'] + 1}/{len(provider['keys'])} for {provider['name']}")
        return True
    
    def _rotate_provider(self):
        """Rotate to the next available provider"""
        if not self.providers:
            return False
        
        # Try rotating key within current provider first
        if self._rotate_api_key():
            return True
        
        # Move to next provider
        if self.current_provider_index < len(self.providers) - 1:
            self.current_provider_index += 1
            provider = self.providers[self.current_provider_index]
            self.api_key = provider['keys'][0]
            self.base_url = provider['base_url']
            logger.info(f"Rotated to provider: {provider['name']}")
            return True
        
        return False  # All providers exhausted
    
    def extract_from_ocr_text(self, ocr_text: str) -> Dict[str, Any]:
        """
        Extract invoice data from OCR text using LLM with multi-provider rotation
        
        Args:
            ocr_text: Raw OCR text from invoice
        
        Returns:
            Structured invoice data
        """
        import httpx
        
        if not self.providers:
            logger.warning("No API providers configured, using regex fallback")
            return self._extract_with_regex(ocr_text)
        
        prompt = f"""Extract all information from this invoice OCR text and return as JSON:

OCR TEXT:
{ocr_text}

Return JSON in this format:
{{
  "invoice_number": "string or null",
  "invoice_date": "YYYY-MM-DD or null",
  "due_date": "YYYY-MM-DD or null",
  "vendor_name": "string or null",
  "vendor_email": "string or null",
  "vendor_phone": "string or null",
  "vendor_address": "string or null",
  "buyer_name": "string or null",
  "buyer_email": "string or null",
  "subtotal": number or null,
  "tax": number or null,
  "total": number or null,
  "currency": "string (e.g., USD, INR, $, ₹)",
  "line_items": [
    {{
      "description": "string",
      "quantity": number,
      "unit_price": number,
      "amount": number
    }}
  ],
  "payment_terms": "string or null",
  "notes": "string or null",
  "missing_fields": ["list of fields that could not be found"],
  "confidence": number between 0 and 1
}}

Rules:
- Return null for fields that don't exist in the invoice
- Extract ALL line items if present
- Use the exact currency symbol shown
- Set confidence lower if OCR text is unclear
- Include all amounts as numbers (not strings)
- CRITICAL: Extract the EXACT values as written on the invoice document
- DO NOT calculate or infer values - extract what is actually printed on the invoice
- If the invoice shows total as 905, extract 905 even if math suggests 804
- Extract the actual subtotal, tax, and total as shown on the document
- This is for forgery detection - we need to compare actual vs expected values"""

        # Reset to first provider
        self.current_provider_index = 0
        provider = self.providers[0]
        self.api_key = provider['keys'][0]
        self.base_url = provider['base_url']
        
        # Retry logic with reduced timeout to fail faster when keys are invalid
        max_attempts_per_provider = 1
        timeout = 30.0
        
        logger.info(f"Starting LLM extraction with {len(self.providers)} provider(s)")
        
        # Try each provider in order
        for provider_idx in range(len(self.providers)):
            provider = self.providers[provider_idx]
            provider_name = provider['name']
            self.base_url = provider['base_url']
            
            # Try each key for this provider
            for key_idx in range(len(provider['keys'])):
                self.api_key = provider['keys'][key_idx]
                provider['current_key_index'] = key_idx
                
                try:
                    logger.info(f"Trying {provider_name} provider, key {key_idx + 1}/{len(provider['keys'])}")
                    
                    if provider['type'] == 'openai_compatible':
                        result = self._call_openai_compatible_api(prompt, provider['model'], timeout)
                    elif provider['type'] == 'huggingface':
                        result = self._call_huggingface_api(prompt, timeout)
                    else:
                        logger.error(f"Unknown provider type: {provider['type']}")
                        continue
                    
                    # Parse JSON
                    import json
                    extracted = json.loads(result)
                    
                    # Add metadata
                    extracted['extraction_method'] = f'llm_{provider_name.lower()}'
                    extracted['model_used'] = provider['model']
                    
                    logger.info(f"LLM extraction successful with {provider_name}, confidence: {extracted.get('confidence', 0)}")
                    return extracted
                    
                except httpx.ConnectTimeout as e:
                    logger.error(f"{provider_name} connection timeout: {e}")
                    continue
                except httpx.HTTPStatusError as e:
                    status = e.response.status_code
                    if status in [401, 429]:
                        logger.error(f"{provider_name} authentication/rate limit error ({status}): {e}")
                        continue
                    logger.error(f"{provider_name} HTTP error ({status}): {e}")
                    continue
                except httpx.HTTPError as e:
                    logger.error(f"{provider_name} HTTP error: {e}")
                    continue
                except json.JSONDecodeError as e:
                    logger.error(f"{provider_name} JSON decode error: {e}")
                    continue
                except Exception as e:
                    logger.error(f"{provider_name} unexpected error: {e}")
                    continue
        
        # All providers failed - check if due to rate limits
        logger.warning("All API providers failed due to rate limits or errors")
        return {
            "error": "rate_limit_exhausted",
            "message": "All API providers rate limited. Please try again later.",
            "retry_after": 3600,
            "extraction_method": "failed",
            "success": False
        }
    
    def _call_openai_compatible_api(self, prompt: str, model: str, timeout: float) -> str:
        """Call OpenAI-compatible API (Groq, OpenRouter)"""
        import httpx
        
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "model": model,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            "temperature": 0.1,
            "max_tokens": 4096,
            "response_format": {"type": "json_object"}
        }
        
        with httpx.Client(timeout=timeout) as client:
            response = client.post(
                f"{self.base_url}/chat/completions",
                headers=headers,
                json=payload
            )
            response.raise_for_status()
            
            result = response.json()
            return result['choices'][0]['message']['content']
    
    def _call_huggingface_api(self, prompt: str, timeout: float) -> str:
        """Call HuggingFace Inference API"""
        import httpx
        
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "inputs": prompt,
            "parameters": {
                "max_new_tokens": 4096,
                "temperature": 0.1,
                "return_full_text": False
            }
        }
        
        with httpx.Client(timeout=timeout) as client:
            response = client.post(
                self.base_url,
                headers=headers,
                json=payload
            )
            response.raise_for_status()
            
            result = response.json()
            # HuggingFace returns different format
            if isinstance(result, list):
                return result[0]['generated_text']
            return result
    
    def _extract_with_regex(self, ocr_text: str) -> Dict[str, Any]:
        """
        Fallback regex-based extraction when LLM API is unavailable
        
        Args:
            ocr_text: Raw OCR text from invoice
        
        Returns:
            Structured invoice data (basic extraction)
        """
        logger.info("Using regex-based extraction as fallback")
        logger.info(f"OCR text length: {len(ocr_text)} characters")
        logger.info(f"OCR text preview: {ocr_text[:500]}")
        
        extracted = {
            'invoice_number': None,
            'invoice_date': None,
            'due_date': None,
            'vendor_name': None,
            'vendor_email': None,
            'vendor_phone': None,
            'vendor_address': None,
            'buyer_name': None,
            'buyer_email': None,
            'subtotal': None,
            'tax': None,
            'total': None,
            'currency': '₹',
            'line_items': [],
            'payment_terms': None,
            'notes': None,
            'missing_fields': [],
            'confidence': 0.5,  # Lower confidence for regex extraction
            'extraction_method': 'regex_fallback',
            'model_used': None
        }
        
        # Extract invoice number (common patterns)
        invoice_num_patterns = [
            r'Invoice\s*No\.?\s*:?\s*([A-Z0-9/-]+)',
            r'Invoice\s*Number\s*:?\s*([A-Z0-9/-]+)',
            r'Bill\s*No\.?\s*:?\s*([A-Z0-9/-]+)',
            r'INV\s*:?\s*([A-Z0-9/-]+)',
            r'Invoice\s*#?\s*:?\s*([A-Z0-9/-]+)',
            r'No\.?\s*:?\s*([A-Z0-9/-]+)',
            r'\b([A-Z]{2,4}[0-9]{4,})\b'  # Pattern like INV12345
        ]
        for pattern in invoice_num_patterns:
            match = re.search(pattern, ocr_text, re.IGNORECASE)
            if match:
                invoice_num = match.group(1).strip()
                # Filter out common false positives
                if len(invoice_num) > 2 and not invoice_num.lower() in ['invoice', 'bill']:
                    extracted['invoice_number'] = invoice_num
                    break
        
        # Extract date (YYYY-MM-DD, DD-MM-YYYY, DD/MM/YYYY, etc.)
        date_patterns = [
            r'\b(\d{4}[-/]\d{2}[-/]\d{2})\b',
            r'\b(\d{2}[-/]\d{2}[-/]\d{4})\b',
            r'\b(\d{2}[-/]\d{2}[-/]\d{2})\b',
            r'\b(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{4})\b',
            r'\bDate\s*:?\s*(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\b'
        ]
        for pattern in date_patterns:
            match = re.search(pattern, ocr_text, re.IGNORECASE)
            if match:
                date_str = match.group(1)
                # Try to normalize to YYYY-MM-DD
                try:
                    if '-' in date_str:
                        parts = date_str.split('-')
                        if len(parts[0]) == 4:
                            extracted['invoice_date'] = date_str
                        elif len(parts[2]) == 4:
                            extracted['invoice_date'] = f"{parts[2]}-{parts[1]}-{parts[0]}"
                        else:
                            extracted['invoice_date'] = date_str
                except:
                    pass
                break
        
        # Extract vendor name (usually at the top, capitalized)
        lines = ocr_text.split('\n')
        for line in lines[:8]:  # Check first 8 lines
            line = line.strip()
            # Skip empty lines, invoice labels, and common headers
            if (len(line) > 3 and 
                'Invoice' not in line and 
                'Bill' not in line and 
                'Date' not in line and
                'Total' not in line and
                'Amount' not in line and
                not line.startswith('No') and
                not line.startswith('#') and
                any(c.isupper() for c in line) and
                any(c.isalpha() for c in line)):
                # This looks like a company name
                extracted['vendor_name'] = line
                break
        
        # Extract amounts (subtotal, tax, total)
        # Look for patterns like "Total: 905" or "Total ₹905"
        amount_patterns = [
            r'(?:Grand\s*)?Total\s*[:=]?\s*[₹$]?\s*([\d,]+\.?\d*)',
            r'Amount\s*[:=]?\s*[₹$]?\s*([\d,]+\.?\d*)',
            r'Payable\s*[:=]?\s*[₹$]?\s*([\d,]+\.?\d*)',
            r'Net\s*Amount\s*[:=]?\s*[₹$]?\s*([\d,]+\.?\d*)',
            r'TOTAL\s*[₹$]?\s*([\d,]+\.?\d*)',
            r'[₹$]\s*([\d,]+\.?\d*)\s*(?:Total|Payable)?$'
        ]
        for pattern in amount_patterns:
            match = re.search(pattern, ocr_text, re.IGNORECASE)
            if match:
                try:
                    amount_str = match.group(1).replace(',', '')
                    amount = float(amount_str)
                    # Filter out unreasonable amounts
                    if 0 < amount < 10000000:  # Between 0 and 10 million
                        extracted['total'] = amount
                        break
                except:
                    pass
        
        # Extract subtotal
        subtotal_patterns = [
            r'Sub\s*Total\s*[:=]?\s*[₹$]?\s*([\d,]+\.?\d*)',
            r'Subtotal\s*[:=]?\s*[₹$]?\s*([\d,]+\.?\d*)',
            r'Before\s*Tax\s*[:=]?\s*[₹$]?\s*([\d,]+\.?\d*)'
        ]
        for pattern in subtotal_patterns:
            match = re.search(pattern, ocr_text, re.IGNORECASE)
            if match:
                try:
                    amount_str = match.group(1).replace(',', '')
                    amount = float(amount_str)
                    if 0 < amount < 10000000:
                        extracted['subtotal'] = amount
                        break
                except:
                    pass
        
        # Extract tax
        tax_patterns = [
            r'(?:Total\s*)?Tax\s*[:=]?\s*[₹$]?\s*([\d,]+\.?\d*)',
            r'GST\s*[:=]?\s*[₹$]?\s*([\d,]+\.?\d*)',
            r'CGST\s*[:=]?\s*[₹$]?\s*([\d,]+\.?\d*)',
            r'SGST\s*[:=]?\s*[₹$]?\s*([\d,]+\.?\d*)',
            r'VAT\s*[:=]?\s*[₹$]?\s*([\d,]+\.?\d*)'
        ]
        for pattern in tax_patterns:
            match = re.search(pattern, ocr_text, re.IGNORECASE)
            if match:
                try:
                    amount_str = match.group(1).replace(',', '')
                    amount = float(amount_str)
                    if 0 <= amount < 10000000:
                        extracted['tax'] = amount
                        break
                except:
                    pass
        
        # Identify missing fields
        for field in ['invoice_number', 'invoice_date', 'total', 'vendor_name']:
            if not extracted.get(field):
                extracted['missing_fields'].append(field)
        
        # Log what was extracted for debugging
        logger.info(f"Regex extraction results:")
        logger.info(f"  Invoice Number: {extracted.get('invoice_number')}")
        logger.info(f"  Invoice Date: {extracted.get('invoice_date')}")
        logger.info(f"  Vendor Name: {extracted.get('vendor_name')}")
        logger.info(f"  Total: {extracted.get('total')}")
        logger.info(f"  Subtotal: {extracted.get('subtotal')}")
        logger.info(f"  Tax: {extracted.get('tax')}")
        
        logger.info(f"Regex extraction completed. Confidence: {extracted['confidence']}")
        return extracted
    
    def extract_from_image_path(self, image_path: str, ocr_service=None) -> Dict[str, Any]:
        """
        Extract invoice data from image by first running OCR, then LLM
        
        Args:
            image_path: Path to image file
            ocr_service: Optional OCR service (if None, uses EasyOCR)
        
        Returns:
            Structured invoice data
        """
        import cv2
        from PIL import Image
        import os
        
        # Validate image file exists and is readable
        if not os.path.exists(image_path):
            raise Exception(f"Image file not found: {image_path}")
        
        # Try to validate and convert image with PIL, but don't fail if it doesn't work
        temp_path = image_path
        try:
            img = Image.open(image_path)
            img.verify()  # Verify it's a valid image
            # Reopen after verify (verify closes the file)
            img = Image.open(image_path)
            # Convert to RGB if needed
            if img.mode != 'RGB':
                img = img.convert('RGB')
            # Save as temporary JPEG for EasyOCR compatibility
            temp_path = image_path + '_temp.jpg'
            img.save(temp_path, 'JPEG', quality=95)
            logger.info(f"Image validated and converted to JPEG: {temp_path}")
        except Exception as e:
            logger.warning(f"Image validation/conversion failed (will try original file): {e}")
            # Continue with original file - EasyOCR might handle it better
            temp_path = image_path
        
        # Run OCR first
        try:
            import easyocr
            reader = easyocr.Reader(['en'], gpu=False, verbose=False)
            results = reader.readtext(temp_path)
            ocr_text = ' '.join([result[1] for result in results])
            logger.info(f"OCR extracted {len(ocr_text)} characters")
            
            # Clean up temp file if created
            if temp_path != image_path and os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except:
                    pass
        except Exception as e:
            logger.error(f"OCR failed: {e}")
            # Clean up temp file if created
            if temp_path != image_path and os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except:
                    pass
            raise Exception(f"OCR failed: {e}")
        
        # Then use LLM to extract structured data
        return self.extract_from_ocr_text(ocr_text)
    
    def validate_extraction(self, extracted: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Validate extracted data with business rules
        
        Returns:
            List of validation warnings
        """
        warnings = []
        
        # Check mathematical consistency
        subtotal = extracted.get('subtotal')
        tax = extracted.get('tax')
        total = extracted.get('total')
        
        if subtotal is not None and tax is not None and total is not None:
            calculated = subtotal + tax
            if abs(calculated - total) > 0.01:
                warnings.append({
                    'type': 'mathematical_inconsistency',
                    'severity': 'high',
                    'message': f'subtotal + tax (${calculated:.2f}) ≠ total (${total:.2f})',
                    'expected': calculated,
                    'found': total
                })
        
        # Check line items sum
        line_items = extracted.get('line_items', [])
        if line_items and total is not None:
            line_sum = sum(item.get('amount', 0) for item in line_items)
            if abs(line_sum - total) > 0.01:
                warnings.append({
                    'type': 'mathematical_inconsistency',
                    'severity': 'high',
                    'message': f'Sum of line items (${line_sum:.2f}) ≠ total (${total:.2f})',
                    'expected': line_sum,
                    'found': total
                })
        
        # Check for negative amounts
        if total is not None and total < 0:
            warnings.append({
                'type': 'invalid_value',
                'severity': 'critical',
                'message': 'Total amount is negative',
                'field': 'total'
            })
        
        # Check missing critical fields
        missing = extracted.get('missing_fields', [])
        critical_fields = ['invoice_number', 'invoice_date', 'total', 'vendor_name']
        for field in critical_fields:
            if field in missing or extracted.get(field) is None:
                warnings.append({
                    'type': 'missing_critical_field',
                    'severity': 'medium',
                    'message': f'Missing critical field: {field}',
                    'field': field
                })
        
        return warnings
    
    def extract_and_validate(self, image_path: str) -> Dict[str, Any]:
        """
        Extract and validate in one call
        
        Returns:
            Dict with extracted data and validation warnings
        """
        extracted = self.extract_from_image_path(image_path)
        warnings = self.validate_extraction(extracted)
        
        return {
            'extracted_data': extracted,
            'validation_warnings': warnings,
            'confidence': extracted.get('confidence', 0.8),
            'needs_verification': len(warnings) > 0 or extracted.get('confidence', 0) < 0.7
        }


def get_groq_extractor() -> LLMInvoiceExtractor:
    """Get LLM extractor with API key from environment"""
    import os
    api_key = os.getenv('GROQ_API_KEY')
    return LLMInvoiceExtractor(api_key)
