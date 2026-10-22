import os

BASE_DIR = os.path.abspath(os.path.dirname(__file__))

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY', 'attendio-production-super-secret-key-2026')
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        'DATABASE_URL', 
        f"sqlite:///{os.path.join(BASE_DIR, 'attendio.db')}"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    
    # QR Token validity in seconds (strictly 80 seconds)
    QR_EXPIRY_SECONDS = int(os.environ.get('QR_EXPIRY_SECONDS', 80))
    
    # Default GPS Geofence values (per college defaults)
    DEFAULT_GEOFENCE_RADIUS_METERS = float(os.environ.get('DEFAULT_GEOFENCE_RADIUS_METERS', 150.0))
    DEFAULT_MAX_ACCURACY_METERS = float(os.environ.get('DEFAULT_MAX_ACCURACY_METERS', 50.0))
    
    # Defaulter attendance threshold percentage (e.g. 75%)
    DEFAULT_DEFAULTER_THRESHOLD = float(os.environ.get('DEFAULT_DEFAULTER_THRESHOLD', 75.0))
    
    # Server Host / URL for QR codes
    SERVER_HOST_URL = os.environ.get('SERVER_HOST_URL', '')
