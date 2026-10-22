from functools import wraps
from flask import request, jsonify, g, current_app
from itsdangerous import URLSafeTimedSerializer, SignatureExpired, BadSignature
from models import db, User

def get_serializer():
    return URLSafeTimedSerializer(current_app.config['SECRET_KEY'])

def generate_auth_token(user_id, role, college_id=None, expires_in=86400):
    """Generate a cryptographically signed token valid for 24 hours (86400s)"""
    s = get_serializer()
    payload = {
        'user_id': user_id,
        'role': role,
        'college_id': college_id
    }
    return s.dumps(payload)

def verify_auth_token(token, max_age=86400):
    """Verify cryptographic signature and expiration of auth token"""
    s = get_serializer()
    try:
        data = s.loads(token, max_age=max_age)
        return data
    except (SignatureExpired, BadSignature):
        return None

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        token = None
        
        if auth_header and auth_header.startswith('Bearer '):
            token = auth_header.split(' ')[1]
        elif 'auth_token' in request.args:
            token = request.args.get('auth_token')
            
        if not token:
            return jsonify({'status': 'failed', 'message': 'Authentication required. Missing token.'}), 401
            
        payload = verify_auth_token(token)
        if not payload:
            return jsonify({'status': 'failed', 'message': 'Invalid or expired authentication token.'}), 401
            
        user = db.session.get(User, payload['user_id'])
        if not user or not user.is_active:
            return jsonify({'status': 'failed', 'message': 'User account not found or deactivated.'}), 401
            
        g.current_user = user
        g.current_college_id = user.college_id
        return f(*args, **kwargs)
    return decorated

def require_role(*roles):
    def decorator(f):
        @wraps(f)
        @require_auth
        def decorated(*args, **kwargs):
            if g.current_user.role not in roles:
                return jsonify({
                    'status': 'failed', 
                    'message': f'Access forbidden. Requires one of roles: {", ".join(roles)}'
                }), 403
            return f(*args, **kwargs)
        return decorated
    return decorator

def enforce_college_isolation(target_college_id):
    """Enforces strict tenant isolation. SUPERADMIN bypasses."""
    if g.current_user.role == 'SUPERADMIN':
        return True
    return g.current_college_id == target_college_id
