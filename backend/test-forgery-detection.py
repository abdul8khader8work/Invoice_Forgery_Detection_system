import requests
import json
import io
import time

def test_forgery_detection():
    """Test comprehensive forgery detection capabilities"""
    print("🔍 Testing Invoice Forgery Detection System")
    print("=" * 60)
    
    base_url = "http://127.0.0.1:8000"
    
    # Test cases for different forgery scenarios
    test_cases = [
        {
            "name": "Normal Invoice - Should Pass",
            "content": b"""INVOICE
ABC Corp Inc.
123 Business St.
City, State 12345

Invoice Number: INV-001
Date: 2024-01-15

Item        Quantity    Price    Total
Services    10          $100.00  $1,000.00
Tax (10%)                       $100.00
TOTAL                          $1,100.00

Payment due within 30 days""",
            "expected_risk": "low",
            "expected_flags": []
        },
        {
            "name": "Altered Amount - High Risk",
            "content": b"""INVOICE
XYZ Company
456 Commerce Ave.
Business City, 67890

Invoice Number: INV-002
Date: 2024-01-20

Item        Quantity    Price    Total
Services    5           $200.00  $1,000.00
Tax (10%)                       $100.00
TOTAL                          $2,500.00  # Altered from $1,100

Payment due immediately""",
            "expected_risk": "high",
            "expected_flags": ["math_validation"]
        },
        {
            "name": "Future Date - Medium Risk",
            "content": b"""INVOICE
Future Corp
789 Tomorrow Blvd.
Future City, 11111

Invoice Number: INV-003
Date: 2024-12-31  # Future date

Item        Quantity    Price    Total
Services    3           $150.00  $450.00
Tax (8%)                        $36.00
TOTAL                          $486.00

Pay in advance""",
            "expected_risk": "medium",
            "expected_flags": ["date_validation"]
        },
        {
            "name": "High Tax Rate - High Risk",
            "content": b"""INVOICE
Tax Evaders LLC
321 High Tax Rd.
Tax City, 54321

Invoice Number: INV-004
Date: 2024-01-10

Item        Quantity    Price    Total
Services    8           $100.00  $800.00
Tax (50%)                       $400.00  # Unusually high tax rate
TOTAL                          $1,200.00

Immediate payment required""",
            "expected_risk": "high",
            "expected_flags": ["tax_validation"]
        },
        {
            "name": "Missing Critical Data - High Risk",
            "content": b"""INVOICE
Empty Corp
000 Missing Data St.
No Data, 00000

Date: 2024-01-05

Item        Quantity    Price    Total
Services    2           $50.00   $100.00
Tax (8%)                        $8.00
# Missing total amount and vendor name details

Pay now""",
            "expected_risk": "high",
            "expected_flags": ["completeness_validation"]
        },
        {
            "name": "Zero Amount - High Risk",
            "content": b"""INVOICE
Zero Amount Inc.
999 Free Blvd.
Free City, 00000

Invoice Number: INV-005
Date: 2024-01-01

Item        Quantity    Price    Total
Free Services   10      $0.00    $0.00
Tax (0%)                        $0.00
TOTAL                          $0.00

No payment needed""",
            "expected_risk": "high",
            "expected_flags": ["amount_validation"]
        }
    ]
    
    results = []
    
    for i, test_case in enumerate(test_cases, 1):
        print(f"\n🧪 Test {i}: {test_case['name']}")
        print("-" * 40)
        
        try:
            # Upload test invoice
            files = {'file': (f'test_{i}.pdf', io.BytesIO(test_case['content']), 'application/pdf')}
            response = requests.post(f'{base_url}/scan', files=files)
            
            if response.status_code == 200:
                data = response.json()
                
                # Extract key results
                risk_score = data.get('risk_score', 0)
                risk_level = data.get('risk_level', 'unknown')
                reasoning = data.get('reasoning', [])
                validation_results = data.get('deterministic_validation', {})
                
                print(f"Risk Score: {risk_score}")
                print(f"Risk Level: {risk_level}")
                print(f"Expected Risk: {test_case['expected_risk']}")
                
                # Check if expected flags are present
                checks = validation_results.get('checks', {})
                found_flags = []
                
                for check_name, check_result in checks.items():
                    if not check_result.get('passed', True):
                        found_flags.append(check_name)
                
                print(f"Found Flags: {found_flags}")
                print(f"Expected Flags: {test_case['expected_flags']}")
                
                # Evaluate test result
                test_passed = True
                
                # Check risk level
                if risk_level != test_case['expected_risk']:
                    print(f"❌ Risk level mismatch: got {risk_level}, expected {test_case['expected_risk']}")
                    test_passed = False
                else:
                    print(f"✅ Risk level correct: {risk_level}")
                
                # Check flags
                missing_flags = set(test_case['expected_flags']) - set(found_flags)
                if missing_flags:
                    print(f"❌ Missing expected flags: {missing_flags}")
                    test_passed = False
                else:
                    print(f"✅ All expected flags found")
                
                # Check extracted data
                extracted_data = data.get('extracted_data', {})
                if extracted_data.get('total') is not None:
                    print(f"✅ Total amount extracted: ${extracted_data['total']}")
                else:
                    print(f"⚠️ Total amount not extracted")
                
                if extracted_data.get('vendor_name'):
                    print(f"✅ Vendor extracted: {extracted_data['vendor_name']}")
                else:
                    print(f"⚠️ Vendor name not extracted")
                
                results.append({
                    'test': test_case['name'],
                    'passed': test_passed,
                    'risk_score': risk_score,
                    'risk_level': risk_level,
                    'flags': found_flags
                })
                
                if test_passed:
                    print(f"✅ TEST PASSED")
                else:
                    print(f"❌ TEST FAILED")
                
            else:
                print(f"❌ Upload failed: {response.status_code}")
                print(f"Response: {response.text}")
                results.append({
                    'test': test_case['name'],
                    'passed': False,
                    'error': f"HTTP {response.status_code}"
                })
                
        except Exception as e:
            print(f"❌ Test error: {e}")
            results.append({
                'test': test_case['name'],
                'passed': False,
                'error': str(e)
            })
        
        time.sleep(1)  # Small delay between tests
    
    # Summary
    print("\n" + "=" * 60)
    print("📊 TEST SUMMARY")
    print("=" * 60)
    
    passed = sum(1 for r in results if r.get('passed', False))
    total = len(results)
    
    print(f"Total Tests: {total}")
    print(f"Passed: {passed}")
    print(f"Failed: {total - passed}")
    print(f"Success Rate: {(passed/total)*100:.1f}%")
    
    print("\nDetailed Results:")
    for result in results:
        status = "✅ PASS" if result.get('passed', False) else "❌ FAIL"
        print(f"{status} - {result['test']}")
        if not result.get('passed', False) and 'error' in result:
            print(f"    Error: {result['error']}")
    
    return passed == total

if __name__ == "__main__":
    success = test_forgery_detection()
    if success:
        print("\n🎉 All forgery detection tests passed!")
    else:
        print("\n⚠️ Some tests failed - review the results above")
    
    input("\nPress Enter to continue...")
