"""
Batch Report Service
Aggregates individual invoice scan results into consolidated batch reports.
"""
from typing import List, Dict, Optional
from datetime import datetime
from sqlalchemy.orm import Session
from app.models.database import Invoice


class BatchReportService:
    def __init__(self, db_session: Session):
        self.db = db_session
    
    def aggregate_batch_results(self, invoice_ids: List[str]) -> Dict:
        """
        Aggregate individual invoice results into batch summary.
        
        Args:
            invoice_ids: List of invoice IDs to aggregate
            
        Returns:
            Dictionary containing:
            {
                "total_invoices": int,
                "successful_scans": int,
                "failed_scans": int,
                "total_amount": float,
                "risk_distribution": {"low": int, "medium": int, "high": int},
                "anomalies_detected": int,
                "invoices": List[Dict]
            }
        """
        invoices = []
        successful_scans = 0
        failed_scans = 0
        total_amount = 0.0
        risk_distribution = {"low": 0, "medium": 0, "high": 0}
        anomalies_detected = 0
        
        for invoice_id in invoice_ids:
            try:
                invoice = self.db.query(Invoice).filter(Invoice.file_id == invoice_id).first()
                if invoice:
                    invoice_data = {
                        "file_id": invoice.file_id,
                        "filename": invoice.filename,
                        "status": "success",
                        "risk_level": invoice.risk_level or "low",
                        "risk_score": float(invoice.risk_score) if invoice.risk_score else 0.0,
                        "amount": float(invoice.extracted_data.get("total", 0)) if invoice.extracted_data else 0.0,
                        "vendor": invoice.extracted_data.get("vendor_name") if invoice.extracted_data else None,
                        "invoice_number": invoice.extracted_data.get("invoice_number") if invoice.extracted_data else None,
                        "needs_verification": invoice.needs_verification,
                        "processing_time": float(invoice.processing_time) if invoice.processing_time else 0.0,
                        "timestamp": invoice.created_at.isoformat() if invoice.created_at else None,
                        "extracted_data": invoice.extracted_data,
                        "validation_results": invoice.validation_results,
                        "ml_results": invoice.ml_results,
                    }
                    
                    invoices.append(invoice_data)
                    successful_scans += 1
                    
                    # Aggregate metrics
                    if invoice.extracted_data:
                        total_amount += float(invoice.extracted_data.get("total", 0))
                    
                    # Risk distribution
                    risk_level = (invoice.risk_level or "low").lower()
                    if risk_level in risk_distribution:
                        risk_distribution[risk_level] += 1
                    
                    # Anomalies detection
                    if invoice.ml_results and invoice.ml_results.get("is_anomaly"):
                        anomalies_detected += 1
                else:
                    # Invoice not found in database
                    invoices.append({
                        "file_id": invoice_id,
                        "filename": "Unknown",
                        "status": "failed",
                        "error": "Invoice not found in database",
                    })
                    failed_scans += 1
            except Exception as e:
                # Error processing invoice
                invoices.append({
                    "file_id": invoice_id,
                    "filename": "Unknown",
                    "status": "failed",
                    "error": str(e),
                })
                failed_scans += 1
        
        return {
            "total_invoices": len(invoice_ids),
            "successful_scans": successful_scans,
            "failed_scans": failed_scans,
            "total_amount": total_amount,
            "risk_distribution": risk_distribution,
            "anomalies_detected": anomalies_detected,
            "invoices": invoices,
        }
    
    def generate_pdf_report(self, batch_data: Dict, batch_id: str) -> Optional[bytes]:
        """
        Generate PDF report from batch data using ReportLab.
        
        Args:
            batch_data: Aggregated batch data from aggregate_batch_results
            batch_id: Batch identifier for the report
            
        Returns:
            PDF bytes or None if generation fails
        """
        try:
            from reportlab.lib import colors
            from reportlab.lib.pagesizes import letter
            from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak
            from reportlab.lib.styles import getSampleStyleSheet
            from reportlab.lib.units import inch
            import io
            
            buffer = io.BytesIO()
            doc = SimpleDocTemplate(
                buffer,
                pagesize=letter,
                rightMargin=72,
                leftMargin=72,
                topMargin=72,
                bottomMargin=18,
            )
            
            elements = []
            styles = getSampleStyleSheet()
            
            # Title
            elements.append(Paragraph("Batch Consolidated Report", styles['Title']))
            elements.append(Spacer(1, 12))
            
            # Batch ID and timestamp
            elements.append(Paragraph(f"Batch ID: {batch_id}", styles['Normal']))
            elements.append(Paragraph(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", styles['Normal']))
            elements.append(Spacer(1, 24))
            
            # Summary table
            summary_data = [
                ['Metric', 'Value'],
                ['Total Invoices', str(batch_data['total_invoices'])],
                ['Successful Scans', str(batch_data['successful_scans'])],
                ['Failed Scans', str(batch_data['failed_scans'])],
                ['Total Amount', f"${batch_data['total_amount']:.2f}"],
                ['Anomalies Detected', str(batch_data['anomalies_detected'])],
            ]
            summary_table = Table(summary_data, colWidths=[3*inch, 2*inch])
            summary_table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                ('FONTSIZE', (0, 0), (-1, 0), 12),
                ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
                ('GRID', (0, 0), (-1, -1), 1, colors.black),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.lightgrey]),
            ]))
            elements.append(summary_table)
            elements.append(Spacer(1, 24))
            
            # Risk distribution
            elements.append(Paragraph("Risk Distribution", styles['Heading2']))
            risk_dist = batch_data['risk_distribution']
            risk_data = [
                ['Risk Level', 'Count'],
                ['Low', str(risk_dist.get('low', 0))],
                ['Medium', str(risk_dist.get('medium', 0))],
                ['High', str(risk_dist.get('high', 0))],
            ]
            risk_table = Table(risk_data, colWidths=[3*inch, 2*inch])
            risk_table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                ('GRID', (0, 0), (-1, -1), 1, colors.black),
            ]))
            elements.append(risk_table)
            elements.append(Spacer(1, 24))
            
            # Per-invoice results
            elements.append(Paragraph("Invoice Results", styles['Heading2']))
            elements.append(Spacer(1, 12))
            
            for invoice in batch_data['invoices']:
                elements.append(Paragraph(f"Filename: {invoice.get('filename', 'Unknown')}", styles['Heading3']))
                elements.append(Paragraph(f"Status: {invoice.get('status', 'Unknown')}", styles['Normal']))
                
                if invoice.get('status') == 'success':
                    elements.append(Paragraph(f"Risk Level: {invoice.get('risk_level', 'N/A').upper()}", styles['Normal']))
                    elements.append(Paragraph(f"Risk Score: {invoice.get('risk_score', 0):.2f}", styles['Normal']))
                    elements.append(Paragraph(f"Amount: ${invoice.get('amount', 0):.2f}", styles['Normal']))
                    if invoice.get('vendor'):
                        elements.append(Paragraph(f"Vendor: {invoice['vendor']}", styles['Normal']))
                    if invoice.get('invoice_number'):
                        elements.append(Paragraph(f"Invoice #: {invoice['invoice_number']}", styles['Normal']))
                else:
                    elements.append(Paragraph(f"Error: {invoice.get('error', 'Unknown error')}", styles['Normal']))
                
                elements.append(Spacer(1, 12))
            
            doc.build(elements)
            return buffer.getvalue()
            
        except ImportError:
            # ReportLab not installed
            print("Warning: ReportLab not installed. PDF generation disabled.")
            return None
        except Exception as e:
            print(f"Error generating PDF: {e}")
            return None
