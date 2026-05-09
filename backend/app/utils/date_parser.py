from datetime import datetime
import re
from typing import Optional

def parse_invoice_date(date_str: str) -> Optional[datetime]:
    """
    Parse invoice dates in multiple formats.
    Handles: DD-MMM-YYYY, DD/MM/YYYY, YYYY-MM-DD, etc.
    """
    if not date_str:
        return None
    
    date_str = date_str.strip()
    
    # List of date formats to try (order matters - most common first)
    formats = [
        '%d-%b-%Y',           # 05-Mar-2026
        '%d-%b-%Y %I:%M:%S %p',  # 05-Mar-2026 09:20:06 PM
        '%d/%m/%Y',           # 05/03/2026
        '%d/%m/%Y %I:%M:%S %p',  # 05/03/2026 09:20:06 PM
        '%Y-%m-%d',           # 2026-03-05
        '%Y-%m-%d %H:%M:%S',  # 2026-03-05 21:20:06
        '%d-%m-%Y',           # 05-03-2026
        '%b %d, %Y',          # Mar 05, 2026
        '%d %b %Y',           # 05 Mar 2026
        '%d %B %Y',           # 05 March 2026
        '%m/%d/%Y',           # 03/05/2026 (US format)
        '%m-%d-%Y',           # 03-05-2026 (US format)
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except ValueError:
            continue
    
    # Fallback: Try to extract date components with regex
    date_pattern = r'(\d{1,2})[-/](\d{1,2}|[A-Za-z]{3})[-/](\d{4})'
    match = re.search(date_pattern, date_str)
    if match:
        day, month, year = match.groups()
        # Convert month name to number if needed
        if month.isdigit():
            month = int(month)
        else:
            month_map = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
                        'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12}
            month = month_map.get(month.lower(), 1)
        try:
            return datetime(int(year), month, int(day))
        except:
            pass
    
    return None

def validate_date_range(invoice_date: datetime) -> dict:
    """
    Validate if the invoice date is within reasonable range.
    Returns validation result with warnings.
    """
    if not invoice_date:
        return {
            'valid': False,
            'warning': 'No date provided',
            'days_in_future': None,
            'days_in_past': None
        }
    
    now = datetime.now()
    days_diff = (invoice_date.date() - now.date()).days
    
    if days_diff > 0:
        # Future date
        if days_diff <= 7:
            return {
                'valid': True,
                'warning': f'Date is {days_diff} days in the future',
                'days_in_future': days_diff,
                'days_in_past': None
            }
        else:
            return {
                'valid': False,
                'warning': f'Date is {days_diff} days in the future (too far)',
                'days_in_future': days_diff,
                'days_in_past': None
            }
    elif days_diff < 0:
        # Past date
        days_past = abs(days_diff)
        if days_past <= 365:
            return {
                'valid': True,
                'warning': None,
                'days_in_future': None,
                'days_in_past': days_past
            }
        else:
            return {
                'valid': False,
                'warning': f'Date is {days_past} days in the past (too old)',
                'days_in_future': None,
                'days_in_past': days_past
            }
    else:
        # Today
        return {
            'valid': True,
            'warning': None,
            'days_in_future': None,
            'days_in_past': None
        }
