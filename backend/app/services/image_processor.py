"""
Invoice OCR Pipeline - Image Preprocessing Module
Phase 1: Image Pre-processing (The "Cleaner")
"""

import cv2
import numpy as np
from typing import Tuple, Optional, List
from dataclasses import dataclass
import logging

logger = logging.getLogger(__name__)


@dataclass
class ProcessedImage:
    """Container for processed image and metadata"""
    image: np.ndarray
    original_shape: Tuple[int, int]
    processed_shape: Tuple[int, int]
    dpi: int
    perspective_corrected: bool


class ImageProcessor:
    """
    Advanced image preprocessing pipeline for invoice OCR.
    Handles DPI scaling, binarization, and perspective correction.
    """
    
    TARGET_DPI = 300
    
    def __init__(self, target_dpi: int = 300):
        self.target_dpi = target_dpi
        logger.info(f"ImageProcessor initialized with target DPI: {target_dpi}")
    
    def process(self, image: np.ndarray) -> ProcessedImage:
        """
        Main processing pipeline.
        
        Args:
            image: Input image as numpy array (BGR format)
            
        Returns:
            ProcessedImage with enhanced quality for OCR
        """
        original_shape = image.shape[:2]
        
        # Step 1: DPI Scaling
        image = self._scale_dpi(image)
        
        # Step 2: Perspective Correction
        perspective_corrected = False
        corrected = self._correct_perspective(image)
        if corrected is not None:
            image = corrected
            perspective_corrected = True
            logger.info("Perspective correction applied")
        
        # Step 3: Binarization Pipeline
        image = self._binarize(image)
        
        processed_shape = image.shape[:2]
        
        return ProcessedImage(
            image=image,
            original_shape=original_shape,
            processed_shape=processed_shape,
            dpi=self.target_dpi,
            perspective_corrected=perspective_corrected
        )
    
    def _scale_dpi(self, image: np.ndarray) -> np.ndarray:
        """
        Scale image to target DPI using cubic interpolation.
        Assumes input is screen capture (~96 DPI) and upscales to 300 DPI.
        """
        # Estimate current DPI based on image dimensions
        # Standard A4 at 96 DPI is ~794x1123, at 300 DPI is ~2480x3508
        height, width = image.shape[:2]
        
        # Calculate scale factor to reach target DPI
        # Assuming typical input is around 96 DPI
        estimated_current_dpi = 96
        scale_factor = self.target_dpi / estimated_current_dpi
        
        new_width = int(width * scale_factor)
        new_height = int(height * scale_factor)
        
        # Use cubic interpolation for best quality
        scaled = cv2.resize(image, (new_width, new_height), interpolation=cv2.INTER_CUBIC)
        
        logger.info(f"DPI scaling: {width}x{height} -> {new_width}x{new_height} "
                   f"(scale: {scale_factor:.2f}x)")
        
        return scaled
    
    def _binarize(self, image: np.ndarray) -> np.ndarray:
        """
        Binarization pipeline:
        1. Convert to Grayscale
        2. Apply Gaussian Blur to reduce noise
        3. Use Adaptive Thresholding with Otsu's method
        """
        # Convert to grayscale if needed
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image.copy()
        
        # Apply Gaussian Blur to reduce noise
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        
        # Adaptive thresholding using Otsu's method
        # Otsu automatically finds optimal threshold value
        _, binary = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        
        logger.info("Binarization completed (Gaussian blur + Otsu thresholding)")
        
        return binary
    
    def _correct_perspective(self, image: np.ndarray) -> Optional[np.ndarray]:
        """
        Perspective correction using Canny edge detection and contour analysis.
        
        Steps:
        1. Canny edge detection
        2. Find contours
        3. Identify document boundary (largest quadrilateral)
        4. Apply 4-point perspective transform
        
        Returns:
            Corrected image or None if correction fails
        """
        # Create a copy for processing
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image.copy()
        
        # Edge detection with Canny
        edges = cv2.Canny(gray, 50, 150)
        
        # Dilate edges to connect gaps
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
        dilated = cv2.dilate(edges, kernel, iterations=2)
        
        # Find contours
        contours, _ = cv2.findContours(dilated, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        if not contours:
            logger.warning("No contours found for perspective correction")
            return None
        
        # Sort contours by area (largest first)
        contours = sorted(contours, key=cv2.contourArea, reverse=True)
        
        # Find the document boundary (quadrilateral)
        doc_contour = None
        for contour in contours[:5]:  # Check top 5 largest contours
            peri = cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, 0.02 * peri, True)
            
            # Looking for quadrilateral (4 corners)
            if len(approx) == 4:
                doc_contour = approx
                break
        
        if doc_contour is None:
            logger.warning("No quadrilateral contour found")
            return None
        
        # Apply 4-point perspective transform
        warped = self._four_point_transform(image, doc_contour.reshape(4, 2))
        
        return warped
    
    def _four_point_transform(self, image: np.ndarray, pts: np.ndarray) -> np.ndarray:
        """
        Apply 4-point perspective transform to flatten the image.
        
        Args:
            image: Input image
            pts: 4 corner points of the document [top-left, top-right, bottom-right, bottom-left]
        
        Returns:
            Flattened image
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
        
        # Destination points for perspective transform
        dst = np.array([
            [0, 0],
            [maxWidth - 1, 0],
            [maxWidth - 1, maxHeight - 1],
            [0, maxHeight - 1]], dtype="float32")
        
        # Compute perspective transform matrix and apply
        M = cv2.getPerspectiveTransform(rect, dst)
        warped = cv2.warpPerspective(image, M, (maxWidth, maxHeight))
        
        return warped
    
    def _order_points(self, pts: np.ndarray) -> np.ndarray:
        """
        Order points in clockwise order: top-left, top-right, bottom-right, bottom-left
        """
        rect = np.zeros((4, 2), dtype="float32")
        
        # Sum and diff to identify corners
        s = pts.sum(axis=1)
        diff = np.diff(pts, axis=1)
        
        # Top-left: smallest sum
        rect[0] = pts[np.argmin(s)]
        # Bottom-right: largest sum
        rect[2] = pts[np.argmax(s)]
        # Top-right: smallest difference
        rect[1] = pts[np.argmin(diff)]
        # Bottom-left: largest difference
        rect[3] = pts[np.argmax(diff)]
        
        return rect


# Convenience function for direct usage
def preprocess_image(image: np.ndarray, target_dpi: int = 300) -> ProcessedImage:
    """Quick access to image preprocessing"""
    processor = ImageProcessor(target_dpi=target_dpi)
    return processor.process(image)
