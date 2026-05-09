"""
Analytics API Endpoints
Provides endpoints for analytics dashboard data and export functionality.
"""
from fastapi import APIRouter, HTTPException, Query, Depends
from fastapi.responses import StreamingResponse
from datetime import datetime, timedelta
from typing import Optional
from sqlalchemy.orm import Session
from sqlalchemy import func, case
import csv
import io
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.units import inch

from app.models.database import get_db, Invoice

router = APIRouter(prefix="/api/analytics", tags=["analytics"])


@router.get("/dashboard")
async def get_analytics_dashboard(
    start_date: Optional[str] = Query(None, description="Start date (ISO format)"),
    end_date: Optional[str] = Query(None, description="End date (ISO format)"),
    db: Session = Depends(get_db)
):
    """
    Get real-time analytics dashboard data.
    Supports date range filtering.
    """
    try:
        # Build date filter
        date_filter = []
        params = {}
        
        if start_date and end_date:
            try:
                start_dt = datetime.fromisoformat(start_date)
                end_dt = datetime.fromisoformat(end_date)
                date_filter.append(Invoice.created_at >= start_dt)
                date_filter.append(Invoice.created_at <= end_dt)
            except ValueError:
                raise HTTPException(status_code=400, detail="Invalid date format. Use ISO format (YYYY-MM-DD)")
        
        # Total scans
        total_scans = db.query(func.count(Invoice.id)).filter(*date_filter).scalar() or 0
        
        # Risk distribution and avg risk score
        risk_query = db.query(
            func.sum(case((Invoice.risk_level == 'high', 1), else_=0)).label('high_risk'),
            func.sum(case((Invoice.risk_level == 'medium', 1), else_=0)).label('medium_risk'),
            func.sum(case((Invoice.risk_level == 'low', 1), else_=0)).label('low_risk'),
            func.avg(Invoice.risk_score).label('avg_risk_score')
        ).filter(*date_filter).first()
        
        high_risk = int(risk_query.high_risk or 0)
        medium_risk = int(risk_query.medium_risk or 0)
        low_risk = int(risk_query.low_risk or 0)
        avg_risk_score = round(float(risk_query.avg_risk_score or 0), 2)
        
        # Verification status
        verification_query = db.query(
            func.sum(case((Invoice.verified == True, 1), else_=0)).label('verified'),
            func.sum(case((Invoice.verified == False, 1), else_=0)).label('unverified')
        ).filter(*date_filter).first()
        
        verified = int(verification_query.verified or 0)
        unverified = int(verification_query.unverified or 0)
        
        # Approved and edited counts
        approval_query = db.query(
            func.sum(case((Invoice.approved_by.isnot(None), 1), else_=0)).label('approved'),
            func.sum(case((Invoice.edited_by.isnot(None), 1), else_=0)).label('edited')
        ).filter(*date_filter).first()
        
        approved = int(approval_query.approved or 0)
        edited = int(approval_query.edited or 0)
        
        # Top vendors with ACTUAL risk score calculation
        vendor_query = db.query(
            Invoice.vendor_name,
            func.count(Invoice.id).label('scans'),
            func.sum(case((Invoice.risk_level == 'high', 1), else_=0)).label('high_risk_count'),
            func.avg(Invoice.risk_score).label('avg_risk_score')
        ).filter(*date_filter).group_by(Invoice.vendor_name).order_by(
            func.count(Invoice.id).desc()
        ).limit(10).all()
        
        top_vendors = [
            {
                "name": v.vendor_name or 'Unknown',
                "scan_count": v.scans,
                "high_risk_count": v.high_risk_count,
                "average_risk_score": round(float(v.avg_risk_score or 0), 2)
            }
            for v in vendor_query
        ]
        
        # Recent activity (last 7 days) with risk breakdown
        seven_days_ago = datetime.now() - timedelta(days=7)
        activity_query = db.query(
            func.date(Invoice.created_at).label('date'),
            func.count(Invoice.id).label('count'),
            func.sum(case((Invoice.risk_level == 'high', 1), else_=0)).label('high_risk'),
            func.sum(case((Invoice.risk_level == 'medium', 1), else_=0)).label('medium_risk'),
            func.sum(case((Invoice.risk_level == 'low', 1), else_=0)).label('low_risk')
        ).filter(
            Invoice.created_at >= seven_days_ago
        ).group_by(
            func.date(Invoice.created_at)
        ).order_by(
            func.date(Invoice.created_at).asc()
        ).all()
        
        recent_activity = [
            {
                "date": str(a.date),
                "count": a.count,
                "high_risk": int(a.high_risk or 0),
                "medium_risk": int(a.medium_risk or 0),
                "low_risk": int(a.low_risk or 0)
            }
            for a in activity_query
        ]
        
        # Calculate average confidence (inverse of risk score)
        avg_confidence = round(max(0, 100 - avg_risk_score), 2)
        
        return {
            "total_scans": total_scans,
            "high_risk_scans": high_risk,
            "medium_risk_scans": medium_risk,
            "low_risk_scans": low_risk,
            "average_confidence": avg_confidence,
            "risk_distribution": {
                "high": high_risk,
                "medium": medium_risk,
                "low": low_risk,
                "avg_score": avg_risk_score
            },
            "verification_status": {
                "verified": verified,
                "unverified": unverified,
                "approved": approved,
                "edited": edited
            },
            "top_vendors": top_vendors,
            "recent_activity": recent_activity,
            "last_updated": datetime.now().isoformat()
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Analytics fetch failed: {str(e)}")


@router.get("/export")
async def export_analytics(
    format: str = Query("csv", regex="^(csv|pdf)$", description="Export format: csv or pdf"),
    start_date: Optional[str] = Query(None, description="Start date (ISO format)"),
    end_date: Optional[str] = Query(None, description="End date (ISO format)"),
    db: Session = Depends(get_db)
):
    """
    Export analytics data as CSV or PDF.
    """
    try:
        # Get analytics data
        analytics_data = await get_analytics_dashboard(start_date, end_date, db)
        
        if format == "csv":
            return _export_csv(analytics_data)
        elif format == "pdf":
            return _export_pdf(analytics_data)
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Export failed: {str(e)}")


def _export_csv(data: dict):
    """Export analytics data as CSV"""
    output = io.StringIO()
    writer = csv.writer(output)
    
    # Write summary
    writer.writerow(["Analytics Dashboard Report"])
    writer.writerow(["Generated At", data['last_updated']])
    writer.writerow([])
    
    # Write summary statistics
    writer.writerow(["Summary Statistics"])
    writer.writerow(["Total Scans", data['total_scans']])
    writer.writerow(["High Risk Scans", data['high_risk_scans']])
    writer.writerow(["Medium Risk Scans", data['medium_risk_scans']])
    writer.writerow(["Low Risk Scans", data['low_risk_scans']])
    writer.writerow(["Average Confidence", data['average_confidence']])
    writer.writerow([])
    
    # Write verification status
    writer.writerow(["Verification Status"])
    writer.writerow(["Verified", data['verification_status']['verified']])
    writer.writerow(["Unverified", data['verification_status']['unverified']])
    writer.writerow(["Approved", data['verification_status']['approved']])
    writer.writerow(["Edited", data['verification_status']['edited']])
    writer.writerow([])
    
    # Write top vendors
    writer.writerow(["Top Vendors"])
    writer.writerow(["Vendor Name", "Scan Count", "High Risk Count", "Average Risk Score"])
    for vendor in data['top_vendors']:
        writer.writerow([
            vendor['name'],
            vendor['scan_count'],
            vendor['high_risk_count'],
            vendor['average_risk_score']
        ])
    writer.writerow([])
    
    # Write recent activity
    writer.writerow(["Recent Activity (Last 7 Days)"])
    writer.writerow(["Date", "Count"])
    for activity in data['recent_activity']:
        writer.writerow([activity['date'], activity['count']])
    
    output.seek(0)
    
    return StreamingResponse(
        io.BytesIO(output.getvalue().encode('utf-8')),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=analytics_report.csv"}
    )


def _export_pdf(data: dict):
    """Export analytics data as PDF using ReportLab"""
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=letter)
    styles = getSampleStyleSheet()
    story = []
    
    # Title
    title = Paragraph("Analytics Dashboard Report", styles['Title'])
    story.append(title)
    story.append(Spacer(1, 12))
    
    # Generated timestamp
    timestamp = Paragraph(f"Generated: {data['last_updated']}", styles['Normal'])
    story.append(timestamp)
    story.append(Spacer(1, 24))
    
    # Summary Statistics
    story.append(Paragraph("Summary Statistics", styles['Heading2']))
    summary_data = [
        ['Metric', 'Value'],
        ['Total Scans', str(data['total_scans'])],
        ['High Risk Scans', str(data['high_risk_scans'])],
        ['Medium Risk Scans', str(data['medium_risk_scans'])],
        ['Low Risk Scans', str(data['low_risk_scans'])],
        ['Average Confidence', f"{data['average_confidence']}%"],
    ]
    summary_table = Table(summary_data, colWidths=[3*inch, 2*inch])
    summary_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, 0), 12),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
        ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
        ('GRID', (0, 0), (-1, -1), 1, colors.black),
    ]))
    story.append(summary_table)
    story.append(Spacer(1, 24))
    
    # Verification Status
    story.append(Paragraph("Verification Status", styles['Heading2']))
    verification_data = [
        ['Status', 'Count'],
        ['Verified', str(data['verification_status']['verified'])],
        ['Unverified', str(data['verification_status']['unverified'])],
        ['Approved', str(data['verification_status']['approved'])],
        ['Edited', str(data['verification_status']['edited'])],
    ]
    verification_table = Table(verification_data, colWidths=[3*inch, 2*inch])
    verification_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, 0), 12),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
        ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
        ('GRID', (0, 0), (-1, -1), 1, colors.black),
    ]))
    story.append(verification_table)
    story.append(Spacer(1, 24))
    
    # Top Vendors
    story.append(Paragraph("Top Vendors", styles['Heading2']))
    vendor_data = [['Vendor Name', 'Scans', 'High Risk', 'Avg Risk Score']]
    for vendor in data['top_vendors']:
        vendor_data.append([
            vendor['name'],
            str(vendor['scan_count']),
            str(vendor['high_risk_count']),
            str(vendor['average_risk_score'])
        ])
    vendor_table = Table(vendor_data, colWidths=[2.5*inch, 1*inch, 1*inch, 1.5*inch])
    vendor_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, 0), 10),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
        ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
        ('GRID', (0, 0), (-1, -1), 1, colors.black),
        ('FONTSIZE', (0, 1), (-1, -1), 9),
    ]))
    story.append(vendor_table)
    story.append(Spacer(1, 24))
    
    # Recent Activity
    story.append(Paragraph("Recent Activity (Last 7 Days)", styles['Heading2']))
    activity_data = [['Date', 'Total', 'High Risk', 'Medium Risk', 'Low Risk']]
    for activity in data['recent_activity']:
        activity_data.append([
            activity['date'],
            str(activity['count']),
            str(activity['high_risk']),
            str(activity['medium_risk']),
            str(activity['low_risk'])
        ])
    activity_table = Table(activity_data, colWidths=[1.5*inch, 0.8*inch, 0.8*inch, 0.8*inch, 0.8*inch])
    activity_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, 0), 10),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
        ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
        ('GRID', (0, 0), (-1, -1), 1, colors.black),
        ('FONTSIZE', (0, 1), (-1, -1), 9),
    ]))
    story.append(activity_table)
    
    doc.build(story)
    buffer.seek(0)
    
    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": "attachment; filename=analytics_report.pdf"}
    )
