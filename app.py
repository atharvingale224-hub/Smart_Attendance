import os
import time
import uuid
from datetime import datetime
from flask import Flask, request, jsonify, render_template, send_file, Response, g
from flask_cors import CORS
from werkzeug.utils import secure_filename
import openpyxl
import csv
import io

from config import Config
from models import (
    db, College, GeofenceConfig, User, Department, 
    AcademicClass, Subject, StudentProfile, TeacherProfile, 
    TimetableSlot, LectureSession, AttendanceRecord, ProxyRiskLog
)
from auth import generate_auth_token, require_auth, require_role, enforce_college_isolation
from services import GeoService, QRTokenService, AttendanceService, ReportService

app = Flask(__name__)
app.config.from_object(Config)
CORS(app)
db.init_app(app)

# -------------------------------------------------------------
# DATABASE INITIALIZATION & SEEDING
# -------------------------------------------------------------
def seed_initial_data():
    """Initializes tables and seeds default multi-college data if empty"""
    with app.app_context():
        db.create_all()
        
        # Ensure all 77 students from Bharati Vidyapeeth are present
        try:
            if StudentProfile.query.count() < 70:
                print("[SEED] Seeding 77 students into database...")
                import seed_77_students
                seed_77_students.run()
        except Exception as e:
            print(f"Auto-seed 77 note: {e}")

        # Ensure Timetable from Bharati Vidyapeeth is present
        try:
            if TimetableSlot.query.count() < 10:
                print("[SEED] Seeding Bharati Vidyapeeth weekly timetable...")
                import seed_timetable
                seed_timetable.run()
        except Exception as e:
            print(f"Auto-seed timetable note: {e}")

        # Ensure Admin account exists for Bharati Vidyapeeth
        try:
            admin_user = User.query.filter_by(email="admin@gcek.ac.in").first()
            if not admin_user:
                college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
                if college:
                    admin_user = User(
                        college_id=college.id,
                        email="admin@gcek.ac.in",
                        full_name="College Admin",
                        role="COLLEGE_ADMIN"
                    )
                    admin_user.set_password("Admin@1234")
                    db.session.add(admin_user)
                    db.session.commit()
        except Exception as e:
            print(f"Auto-seed admin note: {e}")

        # Check if default college exists
        if not College.query.first():
            print("[SEED] Seeding initial Attendio database...")
            
            # 1. Default College & Geofence
            college = College(
                name="Government College of Engineering, Karad",
                code="GCEK",
                domain="gcek.ac.in",
                is_verified=True,
                is_active=True
            )
            db.session.add(college)
            db.session.flush()

            geofence = GeofenceConfig(
                college_id=college.id,
                latitude=16.6800,
                longitude=74.2300,
                radius_meters=150.0,
                max_accuracy_meters=50.0
            )
            db.session.add(geofence)

            # 2. Superadmin & College Admin
            superadmin = User(
                email="superadmin@attendio.org",
                full_name="System Superadmin",
                role="SUPERADMIN"
            )
            superadmin.set_password("Admin@1234")
            db.session.add(superadmin)

            college_admin = User(
                college_id=college.id,
                email="admin@gcek.ac.in",
                full_name="GCEK Principal / Admin",
                role="COLLEGE_ADMIN"
            )
            college_admin.set_password("Admin@1234")
            db.session.add(college_admin)

            # 3. Department, Class & Subjects
            dept = Department(
                college_id=college.id,
                name="Computer Science & Engineering",
                code="CSE"
            )
            db.session.add(dept)
            db.session.flush()

            ac_class = AcademicClass(
                college_id=college.id,
                department_id=dept.id,
                name="Third Year B.Tech CSE",
                semester=5,
                division="A",
                academic_year="2026-2027"
            )
            db.session.add(ac_class)
            db.session.flush()

            subject1 = Subject(
                college_id=college.id,
                department_id=dept.id,
                name="Database Management Systems",
                code="CS501",
                semester=5
            )
            subject2 = Subject(
                college_id=college.id,
                department_id=dept.id,
                name="Operating Systems",
                code="CS502",
                semester=5
            )
            db.session.add_all([subject1, subject2])
            db.session.flush()

            # 4. Teacher User & Profile
            teacher_user = User(
                college_id=college.id,
                email="teacher@gcek.ac.in",
                full_name="Prof. Rajesh Sharma",
                role="TEACHER"
            )
            teacher_user.set_password("Teacher@1234")
            db.session.add(teacher_user)
            db.session.flush()

            teacher_profile = TeacherProfile(
                user_id=teacher_user.id,
                college_id=college.id,
                department_id=dept.id,
                employee_id="FAC-CSE-01",
                designation="Assistant Professor"
            )
            db.session.add(teacher_profile)
            db.session.flush()

            # 5. Timetable Slot
            slot = TimetableSlot(
                college_id=college.id,
                teacher_id=teacher_profile.id,
                class_id=ac_class.id,
                subject_id=subject1.id,
                day_of_week="Monday",
                start_time="10:00",
                end_time="11:00",
                room="Room 304"
            )
            db.session.add(slot)

            # 6. Sample Students
            sample_students = [
                ("PRN2024001", "Atharva Joshi", "atharva@student.gcek.ac.in", "1"),
                ("PRN2024002", "Rohan Patil", "rohan@student.gcek.ac.in", "2"),
                ("PRN2024003", "Sneha Kulkarni", "sneha@student.gcek.ac.in", "3"),
                ("PRN2024004", "Pooja Shinde", "pooja@student.gcek.ac.in", "4"),
                ("PRN2024005", "Vikas Deshmukh", "vikas@student.gcek.ac.in", "5")
            ]

            for prn, name, email, roll in sample_students:
                s_user = User(
                    college_id=college.id,
                    email=email,
                    full_name=name,
                    role="STUDENT"
                )
                s_user.set_password("Student@1234")
                db.session.add(s_user)
                db.session.flush()

                s_prof = StudentProfile(
                    user_id=s_user.id,
                    college_id=college.id,
                    class_id=ac_class.id,
                    prn=prn,
                    roll_no=roll
                )
                db.session.add(s_prof)

            db.session.commit()
            print("[SUCCESS] Initial Attendio database seeded successfully!")

# Auto-initialize database tables and seed data on app start/WSGI load
with app.app_context():
    try:
        seed_initial_data()
    except Exception as e:
        print(f"Database init note: {e}")

# -------------------------------------------------------------
# WEB PORTAL ROUTES (Preserving existing UI + Admin UI)
# -------------------------------------------------------------
@app.route('/')
@app.route('/attend')
def attend_page():
    return render_template('index.html')

@app.route('/admin')
def admin_portal():
    return render_template('admin_dashboard.html')

# -------------------------------------------------------------
# AUTHENTICATION & MULTI-COLLEGE REGISTRATION
# -------------------------------------------------------------
@app.route('/api/auth/login', methods=['POST'])
def login():
    data = request.json or {}
    email = data.get('email', '').strip().lower()
    password = data.get('password', '')

    if not email or not password:
        return jsonify({'status': 'failed', 'message': 'Email and password are required.'}), 400

    user = User.query.filter_by(email=email).first()
    if not user or not user.check_password(password):
        return jsonify({'status': 'failed', 'message': 'Invalid email or password credentials.'}), 401

    if not user.is_active:
        return jsonify({'status': 'failed', 'message': 'Your account is currently disabled. Contact administrator.'}), 403

    token = generate_auth_token(user.id, user.role, user.college_id)
    
    college_data = user.college.to_dict() if user.college else None

    return jsonify({
        'status': 'success',
        'message': 'Login successful.',
        'auth_token': token,
        'user': user.to_dict(),
        'college': college_data
    }), 200

@app.route('/api/auth/register-college', methods=['POST'])
def register_college():
    """Multi-college self-registration"""
    data = request.json or {}
    college_name = data.get('name')
    college_code = data.get('code', '').upper().strip()
    admin_name = data.get('admin_name')
    admin_email = data.get('admin_email', '').strip().lower()
    admin_password = data.get('admin_password')

    if not all([college_name, college_code, admin_name, admin_email, admin_password]):
        return jsonify({'status': 'failed', 'message': 'All college and admin registration fields are required.'}), 400

    if College.query.filter_by(code=college_code).first():
        return jsonify({'status': 'failed', 'message': f'College code {college_code} is already registered.'}), 400

    if User.query.filter_by(email=admin_email).first():
        return jsonify({'status': 'failed', 'message': f'Admin email {admin_email} is already in use.'}), 400

    college = College(
        name=college_name,
        code=college_code,
        domain=admin_email.split('@')[-1] if '@' in admin_email else None,
        is_verified=True,
        is_active=True
    )
    db.session.add(college)
    db.session.flush()

    geofence = GeofenceConfig(
        college_id=college.id,
        latitude=float(data.get('latitude', 16.6800)),
        longitude=float(data.get('longitude', 74.2300)),
        radius_meters=float(data.get('radius_meters', 150.0)),
        max_accuracy_meters=float(data.get('max_accuracy_meters', 50.0))
    )
    db.session.add(geofence)

    admin_user = User(
        college_id=college.id,
        email=admin_email,
        full_name=admin_name,
        role="COLLEGE_ADMIN"
    )
    admin_user.set_password(admin_password)
    db.session.add(admin_user)
    db.session.commit()

    return jsonify({
        'status': 'success',
        'message': f'College {college_name} registered successfully!',
        'college_id': college.id
    }), 201

# -------------------------------------------------------------
# CORE ATTENDANCE API (100% Backwards Compatible + Enhanced)
# -------------------------------------------------------------
@app.route('/api/create-session', methods=['POST', 'GET'])
def create_session():
    """
    Creates or starts an attendance session.
    Accepts teacher authentication if available, or falls back to first teacher profile
    for backwards compatibility with existing Flutter app prototype.
    """
    teacher = None
    auth_header = request.headers.get('Authorization')
    if auth_header and auth_header.startswith('Bearer '):
        from auth import verify_auth_token
        payload = verify_auth_token(auth_header.split(' ')[1])
        if payload and payload.get('role') == 'TEACHER':
            user = User.query.get(payload['user_id'])
            if user:
                teacher = user.teacher_profile

    # Fallback to default teacher if called without auth token (prototype compatibility)
    if not teacher:
        teacher = TeacherProfile.query.first()

    if not teacher:
        return jsonify({'status': 'failed', 'message': 'No registered teacher found.'}), 400

    data = request.json or {}
    slot_id = data.get('slot_id')
    subject_id = data.get('subject_id')
    slot = None

    if slot_id:
        slot = db.session.get(TimetableSlot, slot_id)
        if slot:
            ac_class = slot.academic_class
            subject = slot.subject
            teacher = slot.teacher
    elif subject_id:
        subject = db.session.get(Subject, subject_id)
        ac_class = AcademicClass.query.filter_by(college_id=teacher.college_id).first()
    else:
        # Check current day of week from timetable for this teacher
        now = datetime.now()
        day_name = now.strftime('%A')
        today_slot = TimetableSlot.query.filter_by(teacher_id=teacher.id, day_of_week=day_name).first()
        if today_slot:
            slot = today_slot
            ac_class = slot.academic_class
            subject = slot.subject
        else:
            ac_class = AcademicClass.query.filter_by(college_id=teacher.college_id).first()
            subject = Subject.query.filter_by(college_id=teacher.college_id).first()

    if not ac_class or not subject:
        return jsonify({'status': 'failed', 'message': 'Class or subject configuration missing.'}), 400

    # Classroom Teacher Phone GPS Proximity (50 meters)
    teacher_lat = data.get('teacher_lat')
    teacher_lng = data.get('teacher_lng')
    try:
        if teacher_lat is not None and teacher_lng is not None:
            teacher_lat = float(teacher_lat)
            teacher_lng = float(teacher_lng)
        else:
            teacher_lat = 16.6631
            teacher_lng = 74.2642
    except (ValueError, TypeError):
        teacher_lat = 16.6631
        teacher_lng = 74.2642

    proximity_radius = float(data.get('proximity_radius', 50.0))

    token = QRTokenService.generate_token()
    session = LectureSession(
        college_id=teacher.college_id,
        timetable_slot_id=slot.id if slot else None,
        teacher_id=teacher.id,
        class_id=ac_class.id,
        subject_id=subject.id,
        teacher_lat=teacher_lat,
        teacher_lng=teacher_lng,
        proximity_radius_meters=proximity_radius,
        status='ACTIVE',
        started_at=datetime.utcnow(),
        current_token=token,
        token_generated_at=time.time(),
        token_sequence=1
    )
    db.session.add(session)
    db.session.commit()

    # Dynamic host or configured server URL
    host = request.host_url.rstrip('/')
    student_url = f"{host}/attend?session={session.id}&token={token}"

    return jsonify({
        'status': 'success',
        'session_id': session.id,
        'url': student_url,
        'token': token,
        'valid_for_seconds': app.config['QR_EXPIRY_SECONDS'],
        'class_name': ac_class.name,
        'subject_name': subject.name,
        'subject_code': subject.code,
        'teacher_lat': teacher_lat,
        'teacher_lng': teacher_lng,
        'proximity_radius_meters': proximity_radius,
        'room': slot.room if slot and slot.room else 'LH2'
    }), 200

@app.route('/api/mark-attendance', methods=['POST'])
def mark_attendance():
    """
    Secure dynamic QR + GPS Geofenced Attendance Submission
    """
    data = request.json or {}
    session_id = data.get('session_id')
    prn = data.get('prn')
    submitted_token = data.get('token')
    device_uuid = data.get('device_uuid')
    
    try:
        student_lat = float(data.get('latitude', 0.0))
        student_lng = float(data.get('longitude', 0.0))
        accuracy = float(data.get('accuracy', 10.0))
    except (ValueError, TypeError):
        return jsonify({'status': 'failed', 'message': 'Invalid numerical format for GPS coordinates.'}), 400

    if not session_id or not prn:
        return jsonify({'status': 'failed', 'message': 'Session ID and PRN are required.'}), 400

    ip_address = request.headers.get('X-Forwarded-For', request.remote_addr)
    user_agent = request.headers.get('User-Agent', '')

    result, status_code = AttendanceService.mark_attendance(
        session_id=session_id,
        prn=prn,
        latitude=student_lat,
        longitude=student_lng,
        accuracy=accuracy,
        device_uuid=device_uuid,
        ip_address=ip_address,
        user_agent=user_agent,
        submitted_token=submitted_token
    )

    return jsonify(result), status_code

@app.route('/api/attendance-report', methods=['GET'])
def get_report():
    """
    Attendance records report (100% backwards compatible with existing Flutter Teacher app)
    """
    session_id = request.args.get('session_id')
    if session_id:
        records = AttendanceRecord.query.filter_by(session_id=session_id).order_by(AttendanceRecord.timestamp.desc()).all()
    else:
        # Return most recent 50 attendance records
        records = AttendanceRecord.query.order_by(AttendanceRecord.timestamp.desc()).limit(50).all()

    formatted_records = [
        {
            'prn': r.prn,
            'session_id': r.session_id,
            'timestamp': r.timestamp.strftime("%Y-%m-%d %H:%M:%S") if r.timestamp else "",
            'distance': round(r.distance_meters, 2)
        }
        for r in records
    ]

    return jsonify({
        'total_records': len(formatted_records),
        'records': formatted_records
    }), 200

# -------------------------------------------------------------
# TEACHER WORKFLOW & DYNAMIC ROTATING QR ENDPOINTS
# -------------------------------------------------------------
@app.route('/api/teacher/timetable', methods=['GET'])
@require_role('TEACHER')
def get_teacher_timetable():
    teacher = g.current_user.teacher_profile
    if not teacher:
        return jsonify({'status': 'failed', 'message': 'Teacher profile not found.'}), 404

    slots = TimetableSlot.query.filter_by(teacher_id=teacher.id).all()
    return jsonify({
        'status': 'success',
        'timetable': [s.to_dict() for s in slots]
    }), 200

@app.route('/api/teacher/session/<session_id>/live-qr', methods=['GET'])
def get_live_rotating_qr(session_id):
    """
    Retrieves or rotates the 80-second dynamic QR code token for classroom projector.
    """
    session = db.session.get(LectureSession, session_id)
    if not session:
        return jsonify({'status': 'failed', 'message': 'Session not found.'}), 404

    if session.status != 'ACTIVE':
        return jsonify({'status': 'failed', 'message': 'Session is closed.'}), 400

    token, seconds_remaining = QRTokenService.get_or_rotate_token(session, app.config['QR_EXPIRY_SECONDS'])
    host = request.host_url.rstrip('/')
    student_url = f"{host}/attend?session={session.id}&token={token}"

    return jsonify({
        'status': 'success',
        'session_id': session.id,
        'current_token': token,
        'token_sequence': session.token_sequence,
        'seconds_remaining': seconds_remaining,
        'student_url': student_url,
        'max_validity_seconds': app.config['QR_EXPIRY_SECONDS']
    }), 200

@app.route('/api/teacher/session/<session_id>/end', methods=['POST'])
def end_session(session_id):
    session = db.session.get(LectureSession, session_id)
    if not session:
        return jsonify({'status': 'failed', 'message': 'Session not found.'}), 404

    session.status = 'CLOSED'
    session.closed_at = datetime.utcnow()
    db.session.commit()

    summary = ReportService.get_session_attendance(session.id)
    return jsonify({
        'status': 'success',
        'message': 'Attendance session ended successfully.',
        'summary': summary
    }), 200

# -------------------------------------------------------------
# COLLEGE ADMIN & REPORTING ENDPOINTS
# -------------------------------------------------------------
@app.route('/api/admin/dashboard-stats', methods=['GET'])
def get_admin_dashboard_stats():
    """Returns overview statistics for college admin dashboard"""
    # Grab the active college
    college = College.query.first()
    if not college:
        return jsonify({'status': 'failed', 'message': 'No college configured.'}), 404

    students_count = StudentProfile.query.filter_by(college_id=college.id).count()
    teachers_count = TeacherProfile.query.filter_by(college_id=college.id).count()
    classes_count = AcademicClass.query.filter_by(college_id=college.id).count()
    risk_count = ProxyRiskLog.query.filter_by(college_id=college.id).count()

    recent_sessions = LectureSession.query.filter_by(college_id=college.id).order_by(LectureSession.started_at.desc()).limit(10).all()
    recent_risks = ProxyRiskLog.query.filter_by(college_id=college.id).order_by(ProxyRiskLog.timestamp.desc()).limit(10).all()
    students = StudentProfile.query.filter_by(college_id=college.id).limit(50).all()
    teachers = TeacherProfile.query.filter_by(college_id=college.id).all()
    classes = AcademicClass.query.filter_by(college_id=college.id).all()

    return jsonify({
        'status': 'success',
        'college': college.to_dict(),
        'geofence': college.geofence.to_dict() if college.geofence else None,
        'students_count': students_count,
        'teachers_count': teachers_count,
        'classes_count': classes_count,
        'risk_count': risk_count,
        'recent_sessions': [s.to_dict() for s in recent_sessions],
        'recent_risks': [r.to_dict() for r in recent_risks],
        'students': [st.to_dict() for st in students],
        'teachers': [t.to_dict() for t in teachers],
        'classes': [c.to_dict() for c in classes]
    }), 200

@app.route('/api/admin/geofence', methods=['POST'])
def update_geofence():
    data = request.json or {}
    college = College.query.first()
    if not college:
        return jsonify({'status': 'failed', 'message': 'College not found.'}), 404

    geofence = college.geofence
    if not geofence:
        geofence = GeofenceConfig(college_id=college.id)
        db.session.add(geofence)

    try:
        geofence.latitude = float(data.get('latitude', geofence.latitude))
        geofence.longitude = float(data.get('longitude', geofence.longitude))
        geofence.radius_meters = float(data.get('radius_meters', geofence.radius_meters))
        geofence.max_accuracy_meters = float(data.get('max_accuracy_meters', geofence.max_accuracy_meters))
        db.session.commit()
        return jsonify({'status': 'success', 'message': 'Geofence settings updated successfully.', 'geofence': geofence.to_dict()}), 200
    except ValueError:
        return jsonify({'status': 'failed', 'message': 'Invalid numerical values for coordinates or radius.'}), 400

@app.route('/api/admin/students/<student_id>/reset-device', methods=['POST'])
def reset_student_device(student_id):
    student = db.session.get(StudentProfile, student_id)
    if not student:
        return jsonify({'status': 'failed', 'message': 'Student not found.'}), 404

    old_device = student.registered_device_uuid
    student.registered_device_uuid = None
    student.device_registered_at = None
    db.session.commit()

    return jsonify({
        'status': 'success',
        'message': f"Device binding reset for PRN {student.prn}. Student can now bind their new phone on next attendance scan."
    }), 200

@app.route('/api/reports/session/<session_id>', methods=['GET'])
def get_session_report(session_id):
    data = ReportService.get_session_attendance(session_id)
    if not data:
        return jsonify({'status': 'failed', 'message': 'Session not found.'}), 404
    return jsonify({'status': 'success', 'report': data}), 200

@app.route('/api/reports/session/<session_id>/export-csv', methods=['GET'])
def export_session_csv(session_id):
    csv_data = ReportService.export_session_csv(session_id)
    if not csv_data:
        return jsonify({'status': 'failed', 'message': 'Session not found.'}), 404

    return Response(
        csv_data,
        mimetype="text/csv",
        headers={"Content-disposition": f"attachment; filename=attendio_session_{session_id[:8]}.csv"}
    )

@app.route('/api/reports/session/<session_id>/export-excel', methods=['GET'])
def export_session_excel(session_id):
    excel_data = ReportService.export_session_excel(session_id)
    if not excel_data:
        return jsonify({'status': 'failed', 'message': 'Session not found.'}), 404

    return Response(
        excel_data,
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-disposition": f"attachment; filename=attendio_session_{session_id[:8]}.xlsx"}
    )

@app.route('/api/reports/defaulters', methods=['GET'])
def get_defaulter_report():
    class_id = request.args.get('class_id')
    threshold = float(request.args.get('threshold', 75.0))
    if not class_id:
        # Default to first class if not provided
        c = AcademicClass.query.first()
        class_id = c.id if c else None

    if not class_id:
        return jsonify({'status': 'failed', 'message': 'No classes found.'}), 404

@app.route('/api/student/dashboard', methods=['GET'])
def get_student_dashboard():
    """Returns student profile, subject-wise attendance %, and defaulter status"""
    prn = request.args.get('prn')
    if not prn:
        auth_header = request.headers.get('Authorization')
        if auth_header and auth_header.startswith('Bearer '):
            from auth import verify_auth_token
            payload = verify_auth_token(auth_header.split(' ')[1])
            if payload:
                user = db.session.get(User, payload['user_id'])
                if user and user.student_profile:
                    prn = user.student_profile.prn

    if not prn:
        return jsonify({'status': 'failed', 'message': 'PRN is required.'}), 400

    student = StudentProfile.query.filter_by(prn=prn.upper().strip()).first()
    if not student:
        return jsonify({'status': 'failed', 'message': f'Student with PRN {prn} not found.'}), 404

    ac_class = student.academic_class
    conducted_sessions = LectureSession.query.filter_by(class_id=student.class_id, status='CLOSED').all()
    total_conducted = len(conducted_sessions)

    attendance_records = AttendanceRecord.query.filter_by(student_id=student.id).order_by(AttendanceRecord.timestamp.desc()).all()
    total_present = len(attendance_records)

    overall_percentage = round((total_present / total_conducted * 100.0), 2) if total_conducted > 0 else 100.0
    threshold = float(request.args.get('threshold', 75.0))
    is_defaulter = overall_percentage < threshold

    # Subject-wise calculation
    subjects = Subject.query.filter_by(department_id=ac_class.department_id, semester=ac_class.semester).all() if ac_class else []
    subject_stats = []
    for sub in subjects:
        sub_conducted = [s for s in conducted_sessions if s.subject_id == sub.id]
        total_sub_conducted = len(sub_conducted)
        sub_session_ids = [s.id for s in sub_conducted]
        attended_sub = AttendanceRecord.query.filter(
            AttendanceRecord.student_id == student.id,
            AttendanceRecord.session_id.in_(sub_session_ids)
        ).count() if sub_session_ids else 0
        pct = round((attended_sub / total_sub_conducted * 100.0), 2) if total_sub_conducted > 0 else 100.0
        subject_stats.append({
            'subject_id': sub.id,
            'name': sub.name,
            'code': sub.code,
            'conducted': total_sub_conducted,
            'attended': attended_sub,
            'percentage': pct,
            'is_defaulter': pct < threshold
        })

    history = [
        {
            'session_id': r.session_id,
            'subject_name': r.session.subject.name if r.session and r.session.subject else 'Class Lecture',
            'subject_code': r.session.subject.code if r.session and r.session.subject else '',
            'teacher_name': r.session.teacher.user.full_name if r.session and r.session.teacher and r.session.teacher.user else 'Faculty',
            'timestamp': r.timestamp.strftime('%Y-%m-%d %H:%M:%S') if r.timestamp else '',
            'distance_meters': round(r.distance_meters, 2),
            'status': r.status
        }
        for r in attendance_records
    ]

    return jsonify({
        'status': 'success',
        'student': {
            'id': student.id,
            'prn': student.prn,
            'roll_no': student.roll_no,
            'full_name': student.user.full_name if student.user else '',
            'email': student.user.email if student.user else '',
            'college_name': student.college.name if student.college else '',
            'class_name': ac_class.name if ac_class else '',
            'division': ac_class.division if ac_class else '',
            'semester': ac_class.semester if ac_class else 1
        },
        'overall': {
            'total_conducted': total_conducted,
            'total_present': total_present,
            'attendance_percentage': overall_percentage,
            'threshold': threshold,
            'is_defaulter': is_defaulter,
            'status_label': 'Defaulter Warning' if is_defaulter else 'Good Standing'
        },
        'subjects': subject_stats,
        'history': history
    }), 200

@app.route('/api/student/lookup', methods=['GET'])
def lookup_student():
    """Look up a student by PRN or Roll No to preview their verified name before marking attendance"""
    query = request.args.get('prn', '').strip().upper()
    if not query:
        return jsonify({'status': 'failed', 'message': 'PRN or Roll No is required.'}), 400

    student = StudentProfile.query.filter_by(prn=query).first()
    if not student:
        student = StudentProfile.query.filter_by(roll_no=query).first()
    if not student and query.isdigit():
        roll_int = int(query)
        if 1 <= roll_int <= 77:
            student = StudentProfile.query.filter_by(prn=f"20240716{roll_int:02d}").first()
            if not student:
                student = StudentProfile.query.filter_by(roll_no=f"CSTYA{roll_int}").first()

    if not student:
        return jsonify({'status': 'failed', 'message': f'Student "{query}" not found.'}), 404

    return jsonify({
        'status': 'success',
        'prn': student.prn,
        'roll_no': student.roll_no,
        'name': student.user.full_name if student.user else '',
        'class_name': student.academic_class.name if student.academic_class else '',
        'division': student.academic_class.division if student.academic_class else 'A'
    }), 200

# -------------------------------------------------------------
# TIMETABLE APIS
# -------------------------------------------------------------
@app.route('/api/timetable/weekly', methods=['GET'])
def get_weekly_timetable():
    """Returns the weekly timetable grouped by day for the active college/class"""
    college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
    college_id = college.id if college else None
    
    slots = TimetableSlot.query.filter_by(college_id=college_id).all() if college_id else TimetableSlot.query.all()
    days_order = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    grouped = {day: [] for day in days_order}

    for s in slots:
        d = s.to_dict()
        if s.day_of_week in grouped:
            grouped[s.day_of_week].append(d)

    for day in grouped:
        grouped[day].sort(key=lambda x: x['start_time'])

    return jsonify({
        'status': 'success',
        'college_name': college.name if college else '',
        'timetable': grouped,
        'total_slots': len(slots)
    }), 200

@app.route('/api/timetable/today', methods=['GET'])
def get_today_timetable():
    """Returns today's scheduled lectures from timetable for quick teacher selection"""
    now = datetime.now()
    day_name = now.strftime('%A')
    
    college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
    college_id = college.id if college else None

    slots = TimetableSlot.query.filter_by(college_id=college_id, day_of_week=day_name).order_by(TimetableSlot.start_time).all()
    all_slots = TimetableSlot.query.filter_by(college_id=college_id).order_by(TimetableSlot.day_of_week, TimetableSlot.start_time).all()
    
    return jsonify({
        'status': 'success',
        'current_day': day_name,
        'current_time': now.strftime('%H:%M'),
        'today_slots': [s.to_dict() for s in slots],
        'slots': [s.to_dict() for s in (slots if slots else all_slots)],
        'all_slots': [s.to_dict() for s in all_slots]
    }), 200

@app.route('/api/timetable/slot', methods=['POST'])
def add_timetable_slot():
    """Add a new timetable lecture slot"""
    data = request.json or {}
    college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
    if not college:
        return jsonify({'status': 'failed', 'message': 'College not found.'}), 400

    teacher_id = data.get('teacher_id')
    subject_id = data.get('subject_id')
    class_id = data.get('class_id')
    day_of_week = data.get('day_of_week')
    start_time = data.get('start_time')
    end_time = data.get('end_time')
    room = data.get('room', 'LH2')

    if not all([teacher_id, subject_id, class_id, day_of_week, start_time, end_time]):
        return jsonify({'status': 'failed', 'message': 'All slot fields are required.'}), 400

    slot = TimetableSlot(
        college_id=college.id,
        teacher_id=teacher_id,
        class_id=class_id,
        subject_id=subject_id,
        day_of_week=day_of_week,
        start_time=start_time,
        end_time=end_time,
        room=room
    )
    db.session.add(slot)
    db.session.commit()

    return jsonify({'status': 'success', 'message': 'Timetable slot created successfully!', 'slot': slot.to_dict()}), 201

# -------------------------------------------------------------
# APPLICATION ENTRY POINT
# -------------------------------------------------------------
if __name__ == '__main__':
    seed_initial_data()
    print("[STARTUP] Attendio Smart Multi-College Attendance Platform running on http://0.0.0.0:5000")
    print("[ADMIN] College Admin Console: http://127.0.0.1:5000/admin")
    print("[PORTAL] Student Attendance Portal: http://127.0.0.1:5000/attend")
    app.run(host='0.0.0.0', port=5000, debug=False)