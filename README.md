# Invoice Forgery Detection System

An advanced AI-powered invoice forgery detection system that combines multiple OCR technologies and machine learning models to identify fraudulent invoices with high accuracy.

## 🚀 Features

### Core Capabilities
- **Multi-OCR Support**: PaddleOCR, EasyOCR, and Tesseract for robust text extraction
- **AI-Powered Analysis**: Advanced ML models using PyTorch and scikit-learn
- **Batch Processing**: Handle multiple invoices simultaneously
- **Active Learning**: Continuously improve detection accuracy
- **Cross-Platform**: Flutter frontend for Web, Mobile (Android/iOS), and Desktop
- **Real-time Processing**: FastAPI backend with async task processing
- **Smart Ingestion**: Intelligent document parsing and validation

### Advanced Features
- **PDF Text Extraction**: PyMuPDF for both text and scanned PDFs
- **Image Processing**: OpenCV for document preprocessing
- **Database Integration**: PostgreSQL for persistent storage
- **Authentication**: JWT-based secure authentication
- **Analytics Dashboard**: Comprehensive fraud detection analytics
- **API Documentation**: Auto-generated OpenAPI specifications

## 🏗️ Architecture

### Backend (FastAPI)
```
backend/
├── app/
│   ├── api/           # API routes and endpoints
│   ├── core/           # Core configuration and utilities
│   ├── db/             # Database models and connections
│   ├── models/          # Pydantic models
│   ├── services/        # Business logic
│   └── utils/          # Helper functions
├── ml/                # Machine learning models
├── middleware/         # Custom middleware
└── workers/            # Background task workers
```

### Frontend (Flutter)
```
frontend/
├── lib/
│   ├── core/           # Core configuration and API
│   ├── features/        # Feature modules
│   ├── shared/          # Shared components
│   └── widgets/        # Reusable widgets
├── assets/            # Images and icons
└── web/               # Web build output
```

## 🛠️ Tech Stack

### Backend
- **Framework**: FastAPI 0.104.1
- **Server**: Uvicorn 0.24.0
- **Database**: PostgreSQL with SQLAlchemy 2.0.23
- **OCR**: PaddleOCR 2.7.3, EasyOCR, Tesseract
- **ML/AI**: PyTorch, scikit-learn 1.3.2
- **Image Processing**: OpenCV 4.6.0.66
- **PDF Processing**: PyMuPDF 1.26.7
- **Task Queue**: Celery 5.3.4 with Redis 5.0.1
- **Authentication**: python-jose, passlib
- **Environment**: python-dotenv

### Frontend
- **Framework**: Flutter 3.0+
- **State Management**: Riverpod 2.5.0
- **Routing**: Go Router 17.2.1
- **HTTP Client**: Dio 5.4.0
- **UI Components**: Material Design, fl_chart 0.69.0
- **File Handling**: file_picker 8.0.0, image_picker 1.0.4
- **Authentication**: flutter_secure_storage 9.0.0
- **Build Tools**: MSIX for Windows packaging

## 📋 Prerequisites

### System Requirements
- **Python**: 3.8+
- **Flutter**: 3.0+
- **Node.js**: For web development (optional)
- **PostgreSQL**: 12+ (for production)
- **Redis**: 6+ (for async tasks)

### Platform Support
- **Backend**: Windows, Linux, macOS
- **Frontend**: Windows, Linux, macOS, Android, iOS, Web

## 🚀 Installation

### Backend Setup

1. **Clone the repository**
```bash
git clone https://github.com/abdul8khader8work/Invoice_Forgery_Detection_system.git
cd Invoice_Forgery_Detection_system/backend
```

2. **Create virtual environment**
```bash
python -m venv venv
# Windows
venv\Scripts\activate
# Linux/macOS
source venv/bin/activate
```

3. **Install dependencies**
```bash
pip install -r requirements.txt
```

4. **Environment setup**
```bash
# Copy .env.example to .env and configure
cp .env.example .env
# Edit .env with your API keys and database settings
```

5. **Initialize database**
```bash
# Create database tables
python -c "from app.db.database import engine; from app.models import Base; Base.metadata.create_all(engine)"
```

6. **Start the backend**
```bash
# Development
uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Production
uvicorn main:app --host 0.0.0.0 --port 8000 --workers 4
```

### Frontend Setup

1. **Navigate to frontend directory**
```bash
cd frontend
```

2. **Install Flutter dependencies**
```bash
flutter pub get
```

3. **Run the app**
```bash
# Development
flutter run

# Web
flutter run -d web-server --web-port 3000

# Desktop
flutter run -d windows

# Mobile (ensure device is connected)
flutter run -d android  # or -d ios
```

### Build for Production

```bash
# Web
flutter build web

# Windows
flutter build windows

# Android
flutter build apk --release

# iOS
flutter build ios --release
```

## 🔧 Configuration

### Environment Variables (.env)
```env
# Database
DATABASE_URL=postgresql://user:password@localhost/invoice_db

# Redis
REDIS_URL=redis://localhost:6379

# API Keys
GROQ_API_KEY=your_groq_api_key
OPENROUTER_API_KEY=your_openrouter_api_key

# JWT
SECRET_KEY=your_jwt_secret_key
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30

# File Upload
MAX_FILE_SIZE=50MB
UPLOAD_DIR=./uploads
```

### Backend Configuration
- **CORS**: Configured for development (all origins)
- **Rate Limiting**: Configurable per endpoint
- **Logging**: Structured logging with levels
- **Health Checks**: `/health`, `/api/health` endpoints

### Frontend Configuration
- **API Base URL**: Configured per platform
- **File Size Limits**: 50MB default
- **Timeout Settings**: Platform-specific timeouts
- **Offline Support**: Local storage for critical data

## 📚 API Documentation

### Authentication
```http
POST /api/auth/login
POST /api/auth/register
POST /api/auth/refresh
```

### Invoice Analysis
```http
POST /api/scan/analyze
Content-Type: multipart/form-data

# Response
{
  "is_forged": true,
  "confidence": 0.95,
  "analysis": {
    "text_extracted": "...",
    "suspicious_elements": [...],
    "risk_score": 0.87
  }
}
```

### Batch Processing
```http
POST /api/batch/scan
Content-Type: multipart/form-data

# Response
{
  "batch_id": "uuid",
  "status": "processing",
  "total_files": 10,
  "processed": 0
}
```

### Analytics
```http
GET /api/analytics/overview
GET /api/analytics/fraud-trends
GET /api/analytics/model-performance
```

### Full API Documentation
- **Development**: http://localhost:8000/docs
- **Production**: https://your-domain.com/docs

## 🧪 Testing

### Backend Tests
```bash
# Run all tests
python -m pytest

# Run specific test file
python -m pytest tests/test_scan.py

# Run with coverage
python -m pytest --cov=app tests/
```

### Frontend Tests
```bash
# Run unit tests
flutter test

# Run integration tests
flutter test integration_test/

# Run with coverage
flutter test --coverage
```

### API Testing
```bash
# Test all endpoints
python test-all-apis.py

# Test specific endpoint
python test_scan_with_file.py
```

## 📊 Monitoring & Analytics

### Application Metrics
- **Prometheus**: Metrics collection at `/metrics`
- **Health Checks**: System health monitoring
- **Error Tracking**: Structured error logging
- **Performance**: Request/response timing

### Business Analytics
- **Fraud Detection Rate**: Success rate over time
- **Model Performance**: Accuracy, precision, recall
- **User Activity**: Upload patterns and usage
- **System Load**: Resource utilization metrics

## 🔒 Security

### Authentication & Authorization
- **JWT Tokens**: Secure token-based authentication
- **Password Hashing**: bcrypt for secure password storage
- **Session Management**: Configurable token expiration
- **API Security**: Rate limiting and input validation

### Data Protection
- **File Validation**: Type and size restrictions
- **Input Sanitization**: Protection against injection attacks
- **HTTPS**: Encrypted data transmission
- **Environment Variables**: Sensitive data protection

## 🚀 Deployment

### Docker Deployment
```bash
# Build images
docker-compose build

# Run services
docker-compose up -d

# Scale backend
docker-compose up -d --scale backend=3
```

### Production Considerations
- **Database**: Use managed PostgreSQL service
- **Redis**: Use managed Redis service
- **Load Balancer**: Nginx or cloud load balancer
- **SSL/TLS**: Enable HTTPS for all endpoints
- **Monitoring**: Set up alerting and logging

## 🤝 Contributing

1. **Fork the repository**
2. **Create feature branch**: `git checkout -b feature/amazing-feature`
3. **Commit changes**: `git commit -m 'Add amazing feature'`
4. **Push to branch**: `git push origin feature/amazing-feature`
5. **Open Pull Request**

### Development Guidelines
- **Code Style**: Follow PEP 8 (Python) and Flutter/Dart conventions
- **Testing**: Add tests for new features
- **Documentation**: Update API docs and README
- **Commits**: Use conventional commit messages

### Issue Reporting
- **Bug Reports**: Use issue templates
- **Feature Requests**: Describe use case and requirements
- **Security Issues**: Report privately to maintainers

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **PaddleOCR**: For excellent OCR capabilities
- **FastAPI**: For modern, fast API development
- **Flutter**: For beautiful cross-platform UI
- **OpenCV**: For powerful image processing
- **PyTorch**: For machine learning capabilities

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/abdul8khader8work/Invoice_Forgery_Detection_system/issues)
- **Discussions**: [GitHub Discussions](https://github.com/abdul8khader8work/Invoice_Forgery_Detection_system/discussions)
- **Email**: abdul8khader8work@example.com

---

## 🎯 Quick Start

1. **Clone and setup backend** (5 minutes)
2. **Start backend server** (1 minute)
3. **Setup frontend** (3 minutes)
4. **Run Flutter app** (1 minute)
5. **Upload first invoice** (30 seconds)

**Total time to first result: ~10 minutes!**

---

**Built with ❤️ for secure invoice processing and fraud detection**
