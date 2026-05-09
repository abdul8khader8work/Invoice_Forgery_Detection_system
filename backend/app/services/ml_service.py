import numpy as np
import pandas as pd
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import DBSCAN
from typing import Dict, Any, List
import pickle
from pathlib import Path
import joblib

class MLService:
    """
    Probabilistic Engine - ML anomaly detection for invoice amounts
    """
    
    def __init__(self):
        self.model_path = Path("models/isolation_forest.pkl")
        self.scaler_path = Path("models/scaler.pkl")
        self.model = None
        self.scaler = None
        self.is_trained = False
        
        self._load_or_create_model()
        self._load_training_data()
    
    def _load_or_create_model(self):
        """Load existing model or create new one"""
        if self.model_path.exists() and self.scaler_path.exists():
            try:
                self.model = joblib.load(self.model_path)
                self.scaler = joblib.load(self.scaler_path)
                self.is_trained = True
                print("Loaded existing ML model")
            except Exception as e:
                print(f"Error loading model: {e}")
                self._create_new_model()
        else:
            self._create_new_model()
    
    def _create_new_model(self):
        """Create new ML model"""
        self.model = IsolationForest(
            n_estimators=100,
            contamination=0.1,  # Expect 10% anomalies
            random_state=42,
            n_jobs=-1
        )
        self.scaler = StandardScaler()
        self.is_trained = False
        print("Created new ML model")
    
    def _load_training_data(self):
        """Load historical invoice data for training"""
        # In production, this would load from database
        # For now, create synthetic training data
        self.training_data = self._create_synthetic_training_data()
        
        # Train model if not trained
        if not self.is_trained and len(self.training_data) > 0:
            self._train_model()
    
    def _create_synthetic_training_data(self) -> pd.DataFrame:
        """Create synthetic training data for demonstration"""
        np.random.seed(42)
        n_samples = 1000
        
        # Generate realistic invoice amounts
        subtotals = np.random.lognormal(mean=4, sigma=1, size=n_samples)  # Log-normal distribution
        subtotals = np.clip(subtotals, 10, 10000)  # Reasonable range
        
        # Generate tax amounts (typically 10-20% of subtotal)
        tax_rates = np.random.normal(0.15, 0.03, n_samples)
        tax_rates = np.clip(tax_rates, 0.05, 0.25)  # 5-25% tax
        taxes = subtotals * tax_rates
        
        # Calculate totals
        totals = subtotals + taxes
        
        # Add some anomalies
        anomaly_indices = np.random.choice(n_samples, size=int(0.1 * n_samples), replace=False)
        
        # Make some totals too high or too low
        for idx in anomaly_indices:
            if np.random.random() > 0.5:
                totals[idx] *= np.random.uniform(1.5, 3.0)  # Too high
            else:
                totals[idx] *= np.random.uniform(0.3, 0.7)  # Too low
        
        return pd.DataFrame({
            'subtotal': subtotals,
            'tax': taxes,
            'total': totals,
            'tax_rate': tax_rates
        })
    
    def _train_model(self):
        """Train the anomaly detection model"""
        try:
            # Prepare features
            features = self.training_data[['subtotal', 'tax', 'total', 'tax_rate']].copy()
            
            # Add derived features
            features['tax_ratio'] = features['tax'] / features['subtotal']
            features['total_minus_subtotal'] = features['total'] - features['subtotal']
            
            # Scale features
            features_scaled = self.scaler.fit_transform(features)
            
            # Train model
            self.model.fit(features_scaled)
            self.is_trained = True
            
            # Save model
            self.model_path.parent.mkdir(exist_ok=True)
            joblib.dump(self.model, self.model_path)
            joblib.dump(self.scaler, self.scaler_path)
            print("ML model trained and saved successfully")
            
        except Exception as e:
            print(f"Error training model: {e}")
            self.is_trained = False
    
    def is_available(self) -> bool:
        """Check if ML service is available"""
        return self.is_trained and self.model is not None
    
    async def detect_anomalies(self, extracted_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Detect anomalies in invoice data using ML
        """
        if not self.is_available():
            return {
                'is_anomaly': False,
                'anomaly_score': 0.0,
                'anomaly_reason': 'ML model not available',
                'confidence': 0.0
            }
        
        try:
            # Prepare features for prediction
            features = self._prepare_features(extracted_data)
            
            if features is None:
                return {
                    'is_anomaly': False,
                    'anomaly_score': 0.0,
                    'anomaly_reason': 'Insufficient data for ML analysis',
                    'confidence': 0.0
                }
            
            # Scale features
            features_scaled = self.scaler.transform([features])
            
            # Predict anomaly
            prediction = self.model.predict(features_scaled)[0]  # -1 for anomaly, 1 for normal
            anomaly_score = self.model.decision_function(features_scaled)[0]
            
            # Convert to 0-1 scale (higher = more anomalous)
            normalized_score = max(0, min(1, (0.5 - anomaly_score) / 0.5))
            
            # Determine anomaly reason
            anomaly_reason = self._get_anomaly_reason(features, normalized_score)
            
            return {
                'is_anomaly': prediction == -1,
                'anomaly_score': normalized_score,
                'anomaly_reason': anomaly_reason,
                'confidence': 0.8 if self.is_trained else 0.0,
                'features_used': {
                    'subtotal': features[0],
                    'tax': features[1],
                    'total': features[2],
                    'tax_rate': features[3],
                    'tax_ratio': features[4],
                    'total_minus_subtotal': features[5]
                }
            }
            
        except Exception as e:
            return {
                'is_anomaly': False,
                'anomaly_score': 0.0,
                'anomaly_reason': f'ML analysis error: {str(e)}',
                'confidence': 0.0
            }
    
    def _prepare_features(self, data: Dict[str, Any]) -> List[float]:
        """Prepare features for ML prediction"""
        subtotal = data.get('subtotal')
        tax = data.get('tax')
        total = data.get('total')
        
        if subtotal is None or tax is None or total is None:
            return None
        
        # Calculate derived features
        tax_rate = tax / subtotal if subtotal > 0 else 0
        tax_ratio = tax / subtotal if subtotal > 0 else 0
        total_minus_subtotal = total - subtotal
        
        return [subtotal, tax, total, tax_rate, tax_ratio, total_minus_subtotal]
    
    def _get_anomaly_reason(self, features: List[float], anomaly_score: float) -> str:
        """Generate reason for anomaly detection"""
        subtotal, tax, total, tax_rate, tax_ratio, total_minus_subtotal = features
        
        reasons = []
        
        # Check tax rate anomalies
        if tax_rate < 0.05:
            reasons.append("Unusually low tax rate")
        elif tax_rate > 0.25:
            reasons.append("Unusually high tax rate")
        
        # Check ratio anomalies
        if tax_ratio < 0.05:
            reasons.append("Tax amount seems too low for subtotal")
        elif tax_ratio > 0.30:
            reasons.append("Tax amount seems too high for subtotal")
        
        # Check total anomalies
        if abs(total_minus_subtotal - tax) > (subtotal * 0.1):
            reasons.append("Total amount doesn't match expected subtotal + tax")
        
        # Check amount ranges
        if subtotal > 50000:
            reasons.append("Unusually high invoice amount")
        elif subtotal < 10:
            reasons.append("Unusually low invoice amount")
        
        if reasons:
            return "; ".join(reasons)
        else:
            return f"Statistical anomaly detected (score: {anomaly_score:.3f})"
    
    def add_training_sample(self, invoice_data: Dict[str, Any]):
        """Add new invoice to training data (for continuous learning)"""
        try:
            # Prepare features
            features = self._prepare_features(invoice_data)
            if features is None:
                return
            
            # Add to training data
            new_row = pd.DataFrame([{
                'subtotal': features[0],
                'tax': features[1],
                'total': features[2],
                'tax_rate': features[3]
            }])
            
            self.training_data = pd.concat([self.training_data, new_row], ignore_index=True)
            
            # Retrain model periodically (e.g., every 100 new samples)
            if len(self.training_data) % 100 == 0:
                self._train_model()
                
        except Exception as e:
            print(f"Error adding training sample: {e}")
    
    def get_model_stats(self) -> Dict[str, Any]:
        """Get model statistics"""
        if not self.is_trained:
            return {
                'trained': False,
                'training_samples': 0
            }
        
        return {
            'trained': True,
            'training_samples': len(self.training_data),
            'model_type': 'IsolationForest',
            'contamination_rate': 0.1,
            'feature_count': 6
        }
