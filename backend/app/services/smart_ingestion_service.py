"""
Smart Ingestion Service for Invoice Forgery Detection System
Handles file validation, PDF conversion, and OpenCV preprocessing
"""

import cv2
import numpy as np
from pathlib import Path
from typing import Dict, Any, Tuple, Optional
import mimetypes
import tempfile
import os
from pdf2image import convert_from_path
from PIL import Image

class SmartIngestionService:
    """
    Smart Ingestion Pipeline:
    1. File signature verification
    2. PDF to image conversion (300 DPI)
    3. OpenCV preprocessing (grayscale, blur, edge detection)
    4. Contour detection and perspective transform
    5. Deskewing
    6. Error handling for edge detection failures
    """
    
    def __init__(self, temp_dir: str = "D:/Projects/invoice_forgery_system/temp"):
        self.temp_dir = Path(temp_dir)
        self.temp_dir.mkdir(parents=True, exist_ok=True)
        
        # Allowed MIME types for security
        self.allowed_mimes = {
            'application/pdf': 'pdf',
            'image/jpeg': 'jpg',
            'image/png': 'png',
        }
    
    def verify_file_signature(self, file_bytes: bytes, declared_extension: str) -> Tuple[bool, str]:
        """
        Verify actual file signature matches declared extension
        Returns: (is_valid, actual_extension or error_message)
        """
        # Magic numbers for file signatures
        signatures = {
            b'%PDF': 'pdf',
            b'\xff\xd8\xff': 'jpg',  # JPEG
            b'\x89PNG': 'png',
        }
        
        # Check file signature
        for signature, ext in signatures.items():
            if file_bytes.startswith(signature):
                if ext == declared_extension.lower():
                    return True, ext
                else:
                    return False, f"File signature mismatch: declared as .{declared_extension} but actual is .{ext}"
        
        # If no signature match, try mime type detection
        mime_type, _ = mimetypes.guess_type(f"file.{declared_extension}")
        if mime_type in self.allowed_mimes:
            return True, self.allowed_mimes[mime_type]
        
        return False, f"Unknown file signature or unsupported format"
    
    def convert_pdf_to_image(self, file_path: Path, dpi: int = 300) -> np.ndarray:
        """
        Convert PDF first page to high-resolution image
        Returns: OpenCV-compatible numpy array
        """
        try:
            # Convert PDF to PIL Image
            images = convert_from_path(
                str(file_path),
                dpi=dpi,
                first_page=1,
                last_page=1,
                fmt='jpeg'
            )
            
            if not images:
                raise ValueError("Could not convert PDF - no pages found")
            
            # Convert PIL to OpenCV format
            pil_image = images[0]
            open_cv_image = cv2.cvtColor(np.array(pil_image), cv2.COLOR_RGB2BGR)
            
            return open_cv_image
            
        except Exception as e:
            raise ValueError(f"PDF conversion failed: {str(e)}")
    
    def preprocess_image(self, image: np.ndarray) -> Tuple[np.ndarray, Dict[str, Any]]:
        """
        OpenCV preprocessing pipeline:
        1. Grayscale
        2. Gaussian blur
        3. Canny edge detection
        4. Contour detection
        5. Perspective transform (document scanner effect)
        6. Deskewing
        
        Returns: (processed_image, processing_info)
        """
        processing_info = {
            'steps_completed': [],
            'original_shape': image.shape,
        }
        
        # Step 1: Convert to grayscale
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image
        processing_info['steps_completed'].append('grayscale')
        
        # Step 2: Gaussian blur to reduce noise
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        processing_info['steps_completed'].append('gaussian_blur')
        
        # Step 3: Canny edge detection
        edges = cv2.Canny(blurred, 50, 150)
        processing_info['steps_completed'].append('canny_edges')
        
        # Step 4: Find contours
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        processing_info['contours_found'] = len(contours)
        
        # Step 5: Find largest quadrilateral (the document)
        doc_contour = self._find_document_contour(contours, image.shape)
        
        if doc_contour is None:
            processing_info['steps_completed'].append('document_not_found')
            # Return original with slight enhancement
            enhanced = cv2.convertScaleAbs(gray, alpha=1.2, beta=10)
            return enhanced, processing_info
        
        processing_info['steps_completed'].append('document_contour_found')
        
        # Step 6: Perspective transform
        warped = self._four_point_transform(gray, doc_contour)
        processing_info['steps_completed'].append('perspective_transform')
        
        # Step 7: Deskewing
        deskewed = self._deskew_image(warped)
        processing_info['steps_completed'].append('deskewing')
        
        # Final enhancement
        processed = cv2.convertScaleAbs(deskewed, alpha=1.2, beta=10)
        processing_info['final_shape'] = processed.shape
        
        return processed, processing_info
    
    def _find_document_contour(self, contours, image_shape) -> Optional[np.ndarray]:
        """
        Find the largest quadrilateral contour (likely the document)
        Returns: 4-point contour or None
        """
        if not contours:
            return None
        
        # Sort by area (largest first)
        contours = sorted(contours, key=cv2.contourArea, reverse=True)
        
        # Look for quadrilateral with reasonable area
        image_area = image_shape[0] * image_shape[1]
        
        for contour in contours[:10]:  # Check top 10 largest
            area = cv2.contourArea(contour)
            
            # Must be at least 10% of image and less than 95%
            if area < image_area * 0.1 or area > image_area * 0.95:
                continue
            
            # Approximate polygon
            peri = cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, 0.02 * peri, True)
            
            # If we have 4 corners, it's likely a document
            if len(approx) == 4:
                return approx.reshape(4, 2)
        
        return None
    
    def _four_point_transform(self, image: np.ndarray, pts: np.ndarray) -> np.ndarray:
        """
        Apply perspective transform to get top-down view of document
        """
        # Order points: top-left, top-right, bottom-right, bottom-left
        rect = self._order_points(pts)
        (tl, tr, br, bl) = rect
        
        # Compute width
        widthA = np.sqrt(((br[0] - bl[0]) ** 2) + ((br[1] - bl[1]) ** 2))
        widthB = np.sqrt(((tr[0] - tl[0]) ** 2) + ((tr[1] - tl[1]) ** 2))
        maxWidth = max(int(widthA), int(widthB))
        
        # Compute height
        heightA = np.sqrt(((tr[0] - br[0]) ** 2) + ((tr[1] - br[1]) ** 2))
        heightB = np.sqrt(((tl[0] - bl[0]) ** 2) + ((tl[1] - bl[1]) ** 2))
        maxHeight = max(int(heightA), int(heightB))
        
        # Destination points
        dst = np.array([
            [0, 0],
            [maxWidth - 1, 0],
            [maxWidth - 1, maxHeight - 1],
            [0, maxHeight - 1]], dtype="float32")
        
        # Perspective transform
        M = cv2.getPerspectiveTransform(rect, dst)
        warped = cv2.warpPerspective(image, M, (maxWidth, maxHeight))
        
        return warped
    
    def _order_points(self, pts: np.ndarray) -> np.ndarray:
        """
        Order points in consistent order: top-left, top-right, bottom-right, bottom-left
        """
        rect = np.zeros((4, 2), dtype="float32")
        
        # Sum and difference to find corners
        s = pts.sum(axis=1)
        diff = np.diff(pts, axis=1)
        
        rect[0] = pts[np.argmin(s)]      # Top-left (smallest sum)
        rect[2] = pts[np.argmax(s)]      # Bottom-right (largest sum)
        rect[1] = pts[np.argmin(diff)]   # Top-right (smallest difference)
        rect[3] = pts[np.argmax(diff)]   # Bottom-left (largest difference)
        
        return rect
    
    def _deskew_image(self, image: np.ndarray) -> np.ndarray:
        """
        Correct the tilt of the image
        """
        # Detect skew angle
        coords = np.column_stack(np.where(image > 0))
        
        if len(coords) < 100:  # Not enough data
            return image
        
        angle = cv2.minAreaRect(coords)[-1]
        
        if angle < -45:
            angle = -(90 + angle)
        else:
            angle = -angle
        
        # Only rotate if significant skew
        if abs(angle) < 0.5:
            return image
        
        # Rotate image
        (h, w) = image.shape[:2]
        center = (w // 2, h // 2)
        M = cv2.getRotationMatrix2D(center, angle, 1.0)
        rotated = cv2.warpAffine(image, M, (w, h),
                                  flags=cv2.INTER_CUBIC,
                                  borderMode=cv2.BORDER_REPLICATE)
        
        return rotated
    
    def process_file(self, file_bytes: bytes, filename: str) -> Dict[str, Any]:
        """
        Main processing pipeline
        Returns: Processing result with status and file path
        """
        result = {
            'success': False,
            'status': 'error',
            'file_path': None,
            'message': '',
            'processing_info': {}
        }
        
        try:
            # Get extension
            extension = Path(filename).suffix.lower().lstrip('.')
            
            # Step 1: Verify file signature
            is_valid, signature_result = self.verify_file_signature(file_bytes, extension)
            if not is_valid:
                result['message'] = signature_result
                return result
            
            actual_extension = signature_result
            result['processing_info']['signature_verified'] = True
            result['processing_info']['actual_extension'] = actual_extension
            
            # Create temp file
            temp_file = self.temp_dir / f"input_{os.urandom(4).hex()}.{actual_extension}"
            temp_file.write_bytes(file_bytes)
            
            # Step 2: Load image
            if actual_extension == 'pdf':
                # Convert PDF to image
                image = self.convert_pdf_to_image(temp_file, dpi=300)
                result['processing_info']['pdf_converted'] = True
            else:
                # Load image directly
                image = cv2.imread(str(temp_file))
                if image is None:
                    result['message'] = "Could not load image file"
                    return result
            
            # Step 3: Preprocess image
            processed_image, processing_info = self.preprocess_image(image)
            result['processing_info'].update(processing_info)
            
            # Check if document was found
            if 'document_not_found' in processing_info['steps_completed']:
                result['message'] = "Invoice boundaries not found. Please retake the photo on a darker background."
                result['status'] = 'error'
                # Still save the enhanced version for OCR
                output_path = self.temp_dir / f"processed_{os.urandom(4).hex()}.jpg"
                cv2.imwrite(str(output_path), processed_image)
                result['file_path'] = str(output_path)
                result['success'] = False
                return result
            
            # Step 4: Save processed image
            output_path = self.temp_dir / f"clean_{os.urandom(4).hex()}.jpg"
            cv2.imwrite(str(output_path), processed_image, [cv2.IMWRITE_JPEG_QUALITY, 95])
            
            # Cleanup temp input file
            temp_file.unlink(missing_ok=True)
            
            # Success
            result['success'] = True
            result['status'] = 'clean'
            result['file_path'] = str(output_path)
            result['message'] = 'Ready for OCR'
            
            return result
            
        except Exception as e:
            result['message'] = f"Processing error: {str(e)}"
            return result
    
    def cleanup_temp_files(self, max_age_hours: int = 24):
        """
        Clean up old temporary files
        """
        import time
        current_time = time.time()
        
        for file_path in self.temp_dir.glob("*"):
            if file_path.is_file():
                file_age = current_time - file_path.stat().st_mtime
                if file_age > max_age_hours * 3600:
                    file_path.unlink(missing_ok=True)
