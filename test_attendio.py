import pytest
import time
from app import app, db, seed_initial_data
from models import College, User, StudentProfile, TeacherProfile, AcademicClass, Subject, LectureSession, AttendanceRecord, GeofenceConfig
from services import GeoService, QRTokenService, AttendanceService, ReportService

@pytest.fixture
def client():
    app.config['TESTING'] = True
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
    app.config['QR_EXPIRY_SECONDS'] = 40

    with app.test_client() as client:
        with app.app_context():
            db.drop_all()
            db.create_all()
            seed_initial_data()
        yield client
        with app.app_context():
            db.session.remove()
            db.drop_all()

def test_initial_seed_data(client):
    """Test that default college, admin, teacher, class, and students are properly seeded"""
    with app.app_context():
        college = College.query.filter_by(code='GCEK').first()
        assert college is not None
        assert college.is_verified is True
        
        teacher = User.query.filter_by(email='teacher@gcek.ac.in').first()
        assert teacher is not None
        assert teacher.role == 'TEACHER'
        assert teacher.check_password('Teacher@1234') is True

        students = StudentProfile.query.filter_by(college_id=college.id).all()
        assert len(students) >= 5

def test_login_authentication(client):
    """Test login API with correct and incorrect credentials"""
    # Success
    res = client.post('/api/auth/login', json={
        'email': 'teacher@gcek.ac.in',
        'password': 'Teacher@1234'
    })
    assert res.status_code == 200
    data = res.get_json()
    assert data['status'] == 'success'
    assert 'auth_token' in data

    # Failure
    res_fail = client.post('/api/auth/login', json={
        'email': 'teacher@gcek.ac.in',
        'password': 'WrongPassword!'
    })
    assert res_fail.status_code == 401

def test_create_session(client):
    """Test creating an attendance session with 40s rotating token"""
    res = client.post('/api/create-session')
    assert res.status_code == 200
    data = res.get_json()
    assert data['status'] == 'success'
    assert 'session_id' in data
    assert 'url' in data
    assert 'token' in data
    assert data['valid_for_seconds'] == 40

def test_mark_attendance_success_and_duplicate_prevention(client):
    """Test marking attendance successfully and ensuring duplicate submission is rejected"""
    # 1. Create Session
    create_res = client.post('/api/create-session')
    session_data = create_res.get_json()
    session_id = session_data['session_id']
    token = session_data['token']

    # 2. Mark Attendance (Within campus boundary at 16.6800, 74.2300)
    mark_res = client.post('/api/mark-attendance', json={
        'session_id': session_id,
        'prn': 'PRN2024001',
        'latitude': 16.6800,
        'longitude': 74.2300,
        'accuracy': 15.0,
        'device_uuid': 'phone_device_1001',
        'token': token
    })
    assert mark_res.status_code == 200
    data = mark_res.get_json()
    assert data['status'] == 'success'
    assert 'Attendance successfully marked' in data['message']

    # 3. Duplicate Attendance Prevention: Second attempt with same student must fail
    dup_res = client.post('/api/mark-attendance', json={
        'session_id': session_id,
        'prn': 'PRN2024001',
        'latitude': 16.6800,
        'longitude': 74.2300,
        'accuracy': 15.0,
        'device_uuid': 'phone_device_1001',
        'token': token
    })
    assert dup_res.status_code == 400
    dup_data = dup_res.get_json()
    assert 'already been marked' in dup_data['message']

def test_device_binding_security(client):
    """Test that student account binds to first device and rejects mismatching device"""
    create_res = client.post('/api/create-session')
    session_id = create_res.get_json()['session_id']
    token = create_res.get_json()['token']

    # First device marks attendance (binds account to device_A)
    client.post('/api/mark-attendance', json={
        'session_id': session_id,
        'prn': 'PRN2024002',
        'latitude': 16.6800,
        'longitude': 74.2300,
        'accuracy': 10.0,
        'device_uuid': 'device_A_phone',
        'token': token
    })

    # Second session
    create_res2 = client.post('/api/create-session')
    session_id2 = create_res2.get_json()['session_id']
    token2 = create_res2.get_json()['token']

    # Proxy attempt: Friend on device_B tries to mark attendance for PRN2024002
    proxy_res = client.post('/api/mark-attendance', json={
        'session_id': session_id2,
        'prn': 'PRN2024002',
        'latitude': 16.6800,
        'longitude': 74.2300,
        'accuracy': 10.0,
        'device_uuid': 'device_B_proxy_phone',
        'token': token2
    })
    assert proxy_res.status_code == 403
    assert 'bound to a different mobile device' in proxy_res.get_json()['message']

def test_gps_geofence_boundary_rejection(client):
    """Test that submissions outside configured college campus radius are rejected"""
    create_res = client.post('/api/create-session')
    session_id = create_res.get_json()['session_id']
    token = create_res.get_json()['token']

    # Far away coordinates (e.g. 17.5000, 75.0000 - miles away from campus)
    far_res = client.post('/api/mark-attendance', json={
        'session_id': session_id,
        'prn': 'PRN2024003',
        'latitude': 17.5000,
        'longitude': 75.0000,
        'accuracy': 10.0,
        'device_uuid': 'dev_test_3',
        'token': token
    })
    assert far_res.status_code == 400
    assert 'Outside campus geofence boundary' in far_res.get_json()['message']

def test_poor_gps_accuracy_rejection(client):
    """Test that submissions with poor GPS accuracy (> max_accuracy_meters) are rejected"""
    create_res = client.post('/api/create-session')
    session_id = create_res.get_json()['session_id']
    token = create_res.get_json()['token']

    # Accuracy is 250m (exceeds max 50m limit)
    poor_res = client.post('/api/mark-attendance', json={
        'session_id': session_id,
        'prn': 'PRN2024004',
        'latitude': 16.6800,
        'longitude': 74.2300,
        'accuracy': 250.0,
        'device_uuid': 'dev_test_4',
        'token': token
    })
    assert poor_res.status_code == 400
    assert 'GPS accuracy too poor' in poor_res.get_json()['message']

def test_closed_session_rejection(client):
    """Test that attendance cannot be marked on a closed session"""
    create_res = client.post('/api/create-session')
    session_id = create_res.get_json()['session_id']
    token = create_res.get_json()['token']

    # End the session
    end_res = client.post(f'/api/teacher/session/{session_id}/end')
    assert end_res.status_code == 200

    # Try marking attendance on closed session
    closed_res = client.post('/api/mark-attendance', json={
        'session_id': session_id,
        'prn': 'PRN2024005',
        'latitude': 16.6800,
        'longitude': 74.2300,
        'accuracy': 10.0,
        'device_uuid': 'dev_test_5',
        'token': token
    })
    assert closed_res.status_code == 400
    assert 'already been closed' in closed_res.get_json()['message']

def test_reports_and_defaulters(client):
    """Test session report summary, percentage calculation, and defaulter list"""
    create_res = client.post('/api/create-session')
    session_id = create_res.get_json()['session_id']
    token = create_res.get_json()['token']

    # Mark 2 out of 5 students present
    client.post('/api/mark-attendance', json={
        'session_id': session_id,
        'prn': 'PRN2024001',
        'latitude': 16.6800,
        'longitude': 74.2300,
        'accuracy': 10.0,
        'token': token
    })
    client.post('/api/mark-attendance', json={
        'session_id': session_id,
        'prn': 'PRN2024002',
        'latitude': 16.6800,
        'longitude': 74.2300,
        'accuracy': 10.0,
        'token': token
    })

    # Close session
    client.post(f'/api/teacher/session/{session_id}/end')

    # Get report
    rep_res = client.get(f'/api/reports/session/{session_id}')
    assert rep_res.status_code == 200
    report = rep_res.get_json()['report']
    assert report['total_enrolled'] >= 5
    assert report['total_present'] == 2
    assert report['total_absent'] >= 3
    assert report['attendance_percentage'] == round(2.0 / report['total_enrolled'] * 100.0, 2)

    # Test CSV export
    csv_res = client.get(f'/api/reports/session/{session_id}/export-csv')
    assert csv_res.status_code == 200
    assert b"ATTENDIO ATTENDANCE REPORT" in csv_res.data
    assert b"PRN2024001" in csv_res.data

    # Test Excel export
    excel_res = client.get(f'/api/reports/session/{session_id}/export-excel')
    assert excel_res.status_code == 200
    assert excel_res.headers['Content-Type'] == 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
