import cv2
import numpy as np
from PIL import Image
import pytesseract
import pdf2image
from pathlib import Path
from typing import Dict, List, Any
import time
import re

from app.core.config import settings

# Conditional import for easyocr to avoid PyTorch DLL errors
easyocr = None
if settings.easyocr_enabled:
    try:
        import easyocr
    except ImportError:
        print("EasyOCR not available, using Tesseract only")

# PIL/Pillow compatibility patch for EasyOCR
# Pillow 10.0+ removed ANTIALIAS, EasyOCR needs it
try:
    Image.ANTIALIAS
except AttributeError:
    Image.ANTIALIAS = Image.Resampling.LANCZOS if hasattr(Image, 'Resampling') else Image.LANCZOS

class OCRService:
    def __init__(self):
        self.easyocr_reader = None
        self.setup_tesseract()
        self.setup_easyocr()
    
    def setup_tesseract(self):
        """Setup Tesseract OCR"""
        if Path(settings.tesseract_cmd).exists():
            pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd
        else:
            print(f"Warning: Tesseract not found at {settings.tesseract_cmd}")
    
    def is_available(self) -> bool:
        """Check if OCR service is available"""
        # Check if EasyOCR reader is initialized
        if self.easyocr_reader is not None:
            return True
        
        # Check if Tesseract is available
        try:
            import pytesseract
            pytesseract.get_languages(config='')
            return True
        except:
            return False
    
    def setup_easyocr(self):
        """Setup EasyOCR"""
        if settings.easyocr_enabled:
            try:
                self.easyocr_reader = easyocr.Reader(settings.easyocr_langs)
            except Exception as e:
                print(f"EasyOCR setup failed: {e}")
                self.easyocr_reader = None
    
    def is_available(self) -> bool:
        """Check if OCR services are available"""
        return (self.easyocr_reader is not None) or Path(settings.tesseract_cmd).exists()
    
    async def extract_text(self, file_path: Path) -> Dict[str, Any]:
        """
        Extract text from image or PDF file with preprocessing
        """
        start_time = time.time()
        
        try:
            # Convert PDF to images if needed
            if file_path.suffix.lower() == '.pdf':
                images = self.pdf_to_images(file_path)
            else:
                images = [Image.open(file_path)]
            
            all_text = ""
            all_confidences = []
            bounding_boxes = []
            
            for image in images:
                # Preprocess image
                processed_image = self.preprocess_image(image)
                
                # Extract text using both OCR engines
                tesseract_result = self.extract_with_tesseract(processed_image)
                easyocr_result = await self.extract_with_easyocr(processed_image)
                
                # Combine results (prefer EasyOCR if available)
                if easyocr_result and len(easyocr_result['text']) > len(tesseract_result['text']):
                    all_text += easyocr_result['text'] + "\n"
                    all_confidences.extend(easyocr_result['confidences'])
                    bounding_boxes.extend(easyocr_result['boxes'])
                else:
                    all_text += tesseract_result['text'] + "\n"
                    all_confidences.extend(tesseract_result['confidences'])
                    bounding_boxes.extend(tesseract_result['boxes'])
            
            processing_time = time.time() - start_time
            avg_confidence = np.mean(all_confidences) if all_confidences else 0.0
            
            return {
                'text': all_text.strip(),
                'confidence': avg_confidence,
                'confidences': all_confidences,
                'bounding_boxes': bounding_boxes,
                'processing_time': processing_time,
                'word_count': len(all_text.split())
            }
            
        except Exception as e:
            raise Exception(f"OCR extraction failed: {str(e)}")
    
    def pdf_to_images(self, pdf_path: Path) -> List[Image.Image]:
        """Convert PDF to list of images"""
        try:
            # Set Poppler path for Windows
            poppler_paths = [
                r"C:\poppler\poppler-23.11.0\Library\bin",
                r"C:\poppler\Library\bin",
                r"C:\poppler\bin",
            ]
            
            # Find existing poppler path
            poppler_path = None
            for path in poppler_paths:
                if Path(path).exists():
                    poppler_path = path
                    break
            
            if poppler_path:
                images = pdf2image.convert_from_path(
                    pdf_path, 
                    dpi=300,
                    poppler_path=poppler_path
                )
            else:
                # Try without explicit path (relies on PATH env var)
                images = pdf2image.convert_from_path(pdf_path, dpi=300)
            
            return images
            
        except pdf2image.exceptions.PDFInfoNotInstalledError:
            raise Exception(
                "PDF processing requires Poppler to be installed. "
                "Poppler found at C:\\poppler\\poppler-23.11.0\\Library\\bin "
                "but may need to be added to system PATH. "
                "Alternatively, upload image files (JPG/PNG) instead."
            )
        except Exception as e:
            raise Exception(f"PDF conversion failed: {str(e)}")
    
    def preprocess_image(self, image: Image.Image) -> np.ndarray:
        """
        Preprocess image for better OCR accuracy
        """
        # Convert to numpy array
        img_array = np.array(image)
        
        # Convert to grayscale
        if len(img_array.shape) == 3:
            gray = cv2.cvtColor(img_array, cv2.COLOR_RGB2GRAY)
        else:
            gray = img_array
        
        # Apply adaptive thresholding
        binary = cv2.adaptiveThreshold(
            gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2
        )
        
        # Denoise
        denoised = cv2.medianBlur(binary, 3)
        
        # Enhance contrast
        enhanced = cv2.convertScaleAbs(denoised, alpha=1.5, beta=0)
        
        return enhanced
    
    def extract_with_tesseract(self, image: np.ndarray) -> Dict[str, Any]:
        """Extract text using Tesseract OCR"""
        try:
            # Configure Tesseract for invoice recognition
            config = '--oem 3 --psm 6 -c tessedit_char_whitelist=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.,-$%/?& '
            
            # Get detailed data
            data = pytesseract.image_to_data(image, config=config, output_type=pytesseract.Output.DICT)
            
            text_parts = []
            confidences = []
            boxes = []
            
            n_boxes = len(data['text'])
            for i in range(n_boxes):
                if int(data['conf'][i]) > 0:  # Filter out low confidence detections
                    text = data['text'][i].strip()
                    if text:
                        text_parts.append(text)
                        confidences.append(int(data['conf'][i]) / 100.0)
                        
                        # Bounding box
                        x, y, w, h = data['left'][i], data['top'][i], data['width'][i], data['height'][i]
                        boxes.append({
                            'text': text,
                            'bbox': [x, y, x + w, y + h],
                            'confidence': int(data['conf'][i]) / 100.0
                        })
            
            return {
                'text': ' '.join(text_parts),
                'confidences': confidences,
                'boxes': boxes
            }
            
        except Exception as e:
            print(f"Tesseract error: {e}")
            return {'text': '', 'confidences': [], 'boxes': []}
    
    async def extract_with_easyocr(self, image: np.ndarray) -> Dict[str, Any]:
        """Extract text using EasyOCR"""
        if not self.easyocr_reader:
            return {'text': '', 'confidences': [], 'boxes': []}
        
        try:
            results = self.easyocr_reader.readtext(image)
            
            text_parts = []
            confidences = []
            boxes = []
            
            for (bbox, text, confidence) in results:
                if confidence > 0.5:  # Filter low confidence
                    text_parts.append(text)
                    confidences.append(confidence)
                    
                    # Convert bbox format
                    x_min = min(point[0] for point in bbox)
                    y_min = min(point[1] for point in bbox)
                    x_max = max(point[0] for point in bbox)
                    y_max = max(point[1] for point in bbox)
                    
                    boxes.append({
                        'text': text,
                        'bbox': [int(x_min), int(y_min), int(x_max), int(y_max)],
                        'confidence': confidence
                    })
            
            return {
                'text': ' '.join(text_parts),
                'confidences': confidences,
                'boxes': boxes
            }
            
        except Exception as e:
            print(f"EasyOCR error: {e}")
            return {'text': '', 'confidences': [], 'boxes': []}
