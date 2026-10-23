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
    TimetableSlot, LectureSession, AttendanceRecord, ProxyRiskLog,
    IST, get_ist_now
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

        # Ensure only the official 77 students are present (remove legacy test dummy students)
        try:
            old_dummies = StudentProfile.query.filter(~StudentProfile.prn.like('20240716%')).all()
            if old_dummies:
                for dummy in old_dummies:
                    u_id = dummy.user_id
                    db.session.delete(dummy)
                    if u_id:
                        u = db.session.get(User, u_id)
                        if u:
                            db.session.delete(u)
                db.session.commit()
                print(f"[CLEANUP] Removed {len(old_dummies)} legacy dummy students.")
        except Exception as e:
            print(f"Cleanup legacy students note: {e}")

        # Ensure Mrs. Nayan Patil is updated for MDM-03 (replacing Kulkarni)
        try:
            kulkarni_user = User.query.filter(
                (User.email == 'kulkarni@bvcoek.edu.in') | 
                (User.full_name.like('%Kulkarni%'))
            ).filter(User.role == 'TEACHER').first()
            if kulkarni_user:
                kulkarni_user.full_name = "Mrs. Nayan Patil"
                kulkarni_user.email = "nayan.patil@bvcoek.edu.in"
                if kulkarni_user.teacher_profile:
                    kulkarni_user.teacher_profile.designation = "Assistant Professor (MDM-03)"
                db.session.commit()

            nayan_user = User.query.filter_by(email="nayan.patil@bvcoek.edu.in").first()
            if not nayan_user:
                college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
                dept = Department.query.filter_by(college_id=college.id).first() if college else None
                if college:
                    nayan_user = User(
                        college_id=college.id,
                        email="nayan.patil@bvcoek.edu.in",
                        full_name="Mrs. Nayan Patil",
                        role="TEACHER"
                    )
                    nayan_user.set_password("Teacher@1234")
                    db.session.add(nayan_user)
                    db.session.flush()
                    t_prof = TeacherProfile(
                        user_id=nayan_user.id,
                        college_id=college.id,
                        department_id=dept.id if dept else None,
                        employee_id="FAC-MDM",
                        designation="Assistant Professor"
                    )
                    db.session.add(t_prof)
                    db.session.commit()
        except Exception as e:
            print(f"Update Mrs. Nayan Patil note: {e}")

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
    if not user and email == "upadhye@bvcoek.edu.in":
        user = User.query.filter_by(email="teacher@gcek.ac.in").first()
    elif not user and email == "teacher@gcek.ac.in":
        user = User.query.filter_by(email="upadhye@bvcoek.edu.in").first()

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
@app.route('/api/session/create', methods=['POST', 'GET'])
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
    slot_id = data.get('slot_id') or data.get('timetable_slot_id')
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

    proximity_radius = float(data.get('proximity_radius_meters') or data.get('proximity_radius', 50.0))

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
        started_at=get_ist_now(),
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
        'student_url': student_url,
        'token': token,
        'active_token': token,
        'current_token': token,
        'valid_for_seconds': app.config['QR_EXPIRY_SECONDS'],
        'class_name': ac_class.name,
        'subject_name': subject.name,
        'subject_code': subject.code,
        'teacher_lat': teacher_lat,
        'teacher_lng': teacher_lng,
        'proximity_radius_meters': proximity_radius,
        'room': slot.room if slot and slot.room else 'LH2'
    }), 201

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
            'student_name': r.student.user.full_name if r.student and r.student.user else '',
            'roll_no': r.student.roll_no if r.student else '',
            'session_id': r.session_id,
            'timestamp': r.timestamp.strftime("%Y-%m-%d %I:%M:%S %p") if r.timestamp else "",
            'time_only': r.timestamp.strftime("%I:%M %p") if r.timestamp else "",
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
@app.route('/api/session/<session_id>/rotate-token', methods=['GET', 'POST'])
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
        'token': token,
        'current_token': token,
        'active_token': token,
        'token_sequence': session.token_sequence,
        'seconds_remaining': seconds_remaining,
        'valid_for_seconds': seconds_remaining,
        'url': student_url,
        'student_url': student_url,
        'max_validity_seconds': app.config['QR_EXPIRY_SECONDS']
    }), 200

@app.route('/api/teacher/session/<session_id>/end', methods=['POST'])
@app.route('/api/session/<session_id>/end', methods=['POST'])
def end_session(session_id):
    session = db.session.get(LectureSession, session_id)
    if not session:
        return jsonify({'status': 'failed', 'message': 'Session not found.'}), 404

    session.status = 'CLOSED'
    session.closed_at = get_ist_now()
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

@app.route('/api/reports/export-master-excel', methods=['GET'])
def export_master_excel():
    """Generates and downloads the comprehensive Master Attendance & Defaulter Excel Report (.xlsx)"""
    class_id = request.args.get('class_id')
    excel_data = ReportService.export_master_excel(class_id)
    if not excel_data:
        return jsonify({'status': 'failed', 'message': 'Class not found or no attendance data.'}), 404

    now_str = get_ist_now().strftime("%Y%m%d_%H%M")
    filename = f"Attendio_Master_Attendance_BVCOEK_{now_str}.xlsx"

    return Response(
        excel_data,
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-disposition": f"attachment; filename={filename}"}
    )

@app.route('/api/lectures/history', methods=['GET'])
def get_lecture_history():
    """Returns chronological list of all conducted lectures with present/absent summary"""
    subject_id = request.args.get('subject_id')
    teacher_id = request.args.get('teacher_id')
    
    college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
    college_id = college.id if college else None
    ac_class = AcademicClass.query.filter_by(college_id=college_id).first()
    total_enrolled = StudentProfile.query.filter_by(class_id=ac_class.id).count() if ac_class else 77

    query = LectureSession.query
    if ac_class:
        query = query.filter_by(class_id=ac_class.id)
    if subject_id:
        query = query.filter_by(subject_id=subject_id)
    if teacher_id:
        query = query.filter_by(teacher_id=teacher_id)

    sessions = query.order_by(LectureSession.started_at.desc()).all()

    lectures = []
    for s in sessions:
        present_cnt = len(s.attendance_records) if s.attendance_records else 0
        absent_cnt = max(0, total_enrolled - present_cnt)
        pct = round((present_cnt / total_enrolled * 100.0), 1) if total_enrolled > 0 else 0.0

        lectures.append({
            'session_id': s.id,
            'subject_name': s.subject.name if s.subject else 'Class Lecture',
            'subject_code': s.subject.code if s.subject else '',
            'teacher_name': s.teacher.user.full_name if s.teacher and s.teacher.user else 'Faculty',
            'started_at': s.started_at.isoformat() if s.started_at else None,
            'started_at_ist': s.started_at.strftime('%Y-%m-%d %I:%M %p') if s.started_at else '',
            'date': s.started_at.strftime('%Y-%m-%d') if s.started_at else '',
            'time': s.started_at.strftime('%I:%M %p') if s.started_at else '',
            'status': s.status,
            'total_enrolled': total_enrolled,
            'present_count': present_cnt,
            'absent_count': absent_cnt,
            'attendance_percentage': pct,
            'room': 'LH2'
        })

    return jsonify({
        'status': 'success',
        'total_lectures': len(lectures),
        'lectures': lectures
    }), 200

@app.route('/api/lectures/<session_id>/details', methods=['GET'])
def get_lecture_details(session_id):
    """Detailed Present vs Absent breakdown for a specific lecture session"""
    data = ReportService.get_session_attendance(session_id)
    if not data:
        return jsonify({'status': 'failed', 'message': 'Lecture session not found.'}), 404

    return jsonify({
        'status': 'success',
        'details': data
    }), 200

@app.route('/api/reports/master-matrix', methods=['GET'])
def get_master_matrix():
    """Live attendance matrix of all 77 students and their subject attendance"""
    college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
    college_id = college.id if college else None
    ac_class = AcademicClass.query.filter_by(college_id=college_id).first()
    if not ac_class:
        return jsonify({'status': 'failed', 'message': 'Class not found.'}), 404

    subjects = Subject.query.filter_by(department_id=ac_class.department_id, semester=ac_class.semester).all()
    if not subjects:
        subjects = Subject.query.filter_by(college_id=college_id).all()

    conducted_sessions = LectureSession.query.filter_by(class_id=ac_class.id).all()
    total_conducted = len(conducted_sessions)

    subject_sessions = {}
    for sub in subjects:
        sub_sess = [s.id for s in conducted_sessions if s.subject_id == sub.id]
        subject_sessions[sub.id] = sub_sess

    students = StudentProfile.query.filter_by(class_id=ac_class.id).all()
    def roll_sort_key(st):
        r = st.roll_no or ""
        num_part = ''.join(filter(str.isdigit, r))
        return int(num_part) if num_part else 999
    students.sort(key=roll_sort_key)

    matrix_rows = []
    defaulters_count = 0

    for st in students:
        records = AttendanceRecord.query.filter_by(student_id=st.id).all()
        att_sess_ids = set(r.session_id for r in records)
        total_att = len(att_sess_ids)
        overall_pct = round((total_att / total_conducted * 100.0), 1) if total_conducted > 0 else 0.0
        is_def = overall_pct < 50.0
        if is_def:
            defaulters_count += 1

        sub_map = {}
        for sub in subjects:
            s_ids = subject_sessions.get(sub.id, [])
            cond = len(s_ids)
            att = len(att_sess_ids.intersection(s_ids))
            p = round((att / cond * 100.0), 0) if cond > 0 else 0
            sub_map[sub.code] = {
                'conducted': cond,
                'attended': att,
                'percentage': int(p)
            }

        matrix_rows.append({
            'id': st.id,
            'roll_no': st.roll_no,
            'prn': st.prn,
            'full_name': st.user.full_name if st.user else '',
            'total_attended': total_att,
            'total_conducted': total_conducted,
            'percentage': overall_pct,
            'is_defaulter': is_def,
            'subjects': sub_map
        })

    return jsonify({
        'status': 'success',
        'class_name': ac_class.name,
        'division': ac_class.division,
        'total_students': len(students),
        'total_conducted_sessions': total_conducted,
        'defaulters_count': defaulters_count,
        'subjects': [{'code': s.code, 'name': s.name} for s in subjects],
        'matrix': matrix_rows
    }), 200

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

    data = ReportService.get_defaulter_list(class_id, threshold)
    return jsonify({'status': 'success', 'data': data}), 200

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
    """Returns today's scheduled lectures from timetable for quick teacher selection, filtered by teacher if authenticated"""
    now = datetime.now(IST)
    day_name = now.strftime('%A')
    
    college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
    college_id = college.id if college else None

    # Check if teacher_id is provided in query or from Bearer token
    teacher_id = request.args.get('teacher_id')
    auth_header = request.headers.get('Authorization')
    if not teacher_id and auth_header and auth_header.startswith('Bearer '):
        from auth import verify_auth_token
        payload = verify_auth_token(auth_header.split(' ')[1])
        if payload and payload.get('role') == 'TEACHER':
            user = db.session.get(User, payload['user_id'])
            if user and user.teacher_profile:
                teacher_id = user.teacher_profile.id

    if teacher_id:
        slots = TimetableSlot.query.filter_by(teacher_id=teacher_id, day_of_week=day_name).order_by(TimetableSlot.start_time).all()
        all_slots = TimetableSlot.query.filter_by(teacher_id=teacher_id).order_by(TimetableSlot.day_of_week, TimetableSlot.start_time).all()
    else:
        slots = TimetableSlot.query.filter_by(college_id=college_id, day_of_week=day_name).order_by(TimetableSlot.start_time).all()
        all_slots = TimetableSlot.query.filter_by(college_id=college_id).order_by(TimetableSlot.day_of_week, TimetableSlot.start_time).all()
    
    return jsonify({
        'status': 'success',
        'current_day': day_name,
        'current_time': now.strftime('%I:%M %p'),
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
# ADMIN FACULTY & SUBJECT MANAGEMENT ENDPOINTS
# -------------------------------------------------------------
@app.route('/api/admin/teachers/add', methods=['POST'])
def admin_add_teacher():
    """College Admin endpoint to register a new teacher"""
    data = request.json or {}
    full_name = data.get('full_name', '').strip()
    email = data.get('email', '').strip().lower()
    employee_id = data.get('employee_id', '').strip()
    designation = data.get('designation', 'Assistant Professor').strip()
    password = data.get('password', 'Teacher@1234')
    department_id = data.get('department_id')
    is_class_teacher = bool(data.get('is_class_teacher', False))

    if not full_name or not email:
        return jsonify({'status': 'failed', 'message': 'Full name and email are required.'}), 400

    existing_user = User.query.filter_by(email=email).first()
    if existing_user:
        return jsonify({'status': 'failed', 'message': f'Email {email} is already in use.'}), 400

    college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
    if not college:
        return jsonify({'status': 'failed', 'message': 'No college found.'}), 400

    if not department_id:
        dept = Department.query.filter_by(college_id=college.id).first()
        department_id = dept.id if dept else None

    if is_class_teacher and "Class Teacher" not in designation:
        designation += " & Class Teacher"

    user = User(
        college_id=college.id,
        email=email,
        full_name=full_name,
        role="TEACHER"
    )
    user.set_password(password)
    db.session.add(user)
    db.session.flush()

    teacher = TeacherProfile(
        user_id=user.id,
        college_id=college.id,
        department_id=department_id,
        employee_id=employee_id or f"FAC-{user.id[:6].upper()}",
        designation=designation
    )
    db.session.add(teacher)
    db.session.commit()

    return jsonify({
        'status': 'success',
        'message': f'Teacher {full_name} added successfully! Login: {email}',
        'teacher': teacher.to_dict()
    }), 201

@app.route('/api/admin/subjects/add', methods=['POST'])
def admin_add_subject():
    """College Admin endpoint to add a new subject"""
    data = request.json or {}
    name = data.get('name', '').strip()
    code = data.get('code', '').strip().upper()
    semester = int(data.get('semester', 5))
    department_id = data.get('department_id')

    if not name or not code:
        return jsonify({'status': 'failed', 'message': 'Subject name and code are required.'}), 400

    college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
    if not college:
        return jsonify({'status': 'failed', 'message': 'No college found.'}), 400

    if not department_id:
        dept = Department.query.filter_by(college_id=college.id).first()
        department_id = dept.id if dept else None

    existing_sub = Subject.query.filter_by(college_id=college.id, code=code).first()
    if existing_sub:
        return jsonify({'status': 'failed', 'message': f'Subject with code {code} already exists.'}), 400

    subject = Subject(
        college_id=college.id,
        department_id=department_id,
        name=name,
        code=code,
        semester=semester
    )
    db.session.add(subject)
    db.session.commit()

    return jsonify({
        'status': 'success',
        'message': f'Subject {name} ({code}) added successfully!',
        'subject': subject.to_dict()
    }), 201

@app.route('/api/admin/subjects', methods=['GET'])
def admin_get_subjects():
    college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
    college_id = college.id if college else None
    subjects = Subject.query.filter_by(college_id=college_id).all() if college_id else Subject.query.all()
    return jsonify({
        'status': 'success',
        'subjects': [s.to_dict() for s in subjects]
    }), 200

# -------------------------------------------------------------
# CLASS TEACHER & DEFAULTER ANALYSIS (<50%) ENDPOINTS
# -------------------------------------------------------------
@app.route('/api/class-teacher/dashboard-data', methods=['GET'])
def get_class_teacher_dashboard():
    """
    Returns full-class attendance ledger and defaulter list (< 50%) for all 77 students,
    including subject-wise breakdown for AI, CA, JP, OOMD, MDM-03, OE-03.
    """
    college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
    college_id = college.id if college else None

    ac_class = AcademicClass.query.filter_by(college_id=college_id).first()
    if not ac_class:
        return jsonify({'status': 'failed', 'message': 'Class not found.'}), 404

    # All subjects for this class
    subjects = Subject.query.filter_by(department_id=ac_class.department_id, semester=ac_class.semester).all()
    if not subjects:
        subjects = Subject.query.filter_by(college_id=college_id).all()

    # All sessions conducted in this class
    conducted_sessions = LectureSession.query.filter_by(class_id=ac_class.id).all()
    total_conducted = len(conducted_sessions)

    # Subject conducted counts and session ID mappings
    subject_sessions = {}
    for sub in subjects:
        sub_sess = [s.id for s in conducted_sessions if s.subject_id == sub.id]
        subject_sessions[sub.id] = sub_sess

    # Query all students in this class ordered by Roll No integer
    students = StudentProfile.query.filter_by(class_id=ac_class.id).all()
    def roll_sort_key(st):
        r = st.roll_no or ""
        num_part = ''.join(filter(str.isdigit, r))
        return int(num_part) if num_part else 999
    students.sort(key=roll_sort_key)

    students_data = []
    defaulters_data = []

    for st in students:
        records = AttendanceRecord.query.filter_by(student_id=st.id).all()
        attended_session_ids = set(r.session_id for r in records)
        total_attended = len(attended_session_ids)

        # Overall percentage
        overall_pct = round((total_attended / total_conducted * 100.0), 1) if total_conducted > 0 else 0.0
        is_defaulter = overall_pct < 50.0  # Strict user criteria: < 50%

        # Subject-wise breakdown
        sub_breakdown = []
        for sub in subjects:
            sub_sess_ids = subject_sessions.get(sub.id, [])
            sub_conducted = len(sub_sess_ids)
            sub_attended = len(attended_session_ids.intersection(sub_sess_ids))
            sub_pct = round((sub_attended / sub_conducted * 100.0), 1) if sub_conducted > 0 else 0.0
            sub_breakdown.append({
                'subject_id': sub.id,
                'name': sub.name,
                'code': sub.code,
                'conducted': sub_conducted,
                'attended': sub_attended,
                'percentage': sub_pct,
                'is_defaulter': sub_pct < 50.0
            })

        st_entry = {
            'id': st.id,
            'prn': st.prn,
            'roll_no': st.roll_no,
            'full_name': st.user.full_name if st.user else '',
            'email': st.user.email if st.user else '',
            'total_conducted': total_conducted,
            'total_attended': total_attended,
            'percentage': overall_pct,
            'is_defaulter': is_defaulter,
            'subject_breakdown': sub_breakdown
        }

        students_data.append(st_entry)
        if is_defaulter:
            defaulters_data.append(st_entry)

    avg_pct = round(sum(s['percentage'] for s in students_data) / len(students_data), 1) if students_data else 0.0

    return jsonify({
        'status': 'success',
        'class_name': ac_class.name,
        'division': ac_class.division,
        'total_conducted_sessions': total_conducted,
        'total_students': len(students_data),
        'defaulters_count': len(defaulters_data),
        'good_standing_count': len(students_data) - len(defaulters_data),
        'average_attendance_percentage': avg_pct,
        'threshold': 50.0,
        'defaulters': defaulters_data,
        'students': students_data,
        'subjects': [{'id': s.id, 'name': s.name, 'code': s.code} for s in subjects]
    }), 200

@app.route('/api/class-teacher/student/<student_id_or_prn>', methods=['GET'])
def get_class_teacher_student_detail(student_id_or_prn):
    """Detailed attendance audit ledger for a specific student"""
    student = StudentProfile.query.filter(
        (StudentProfile.id == student_id_or_prn) | 
        (StudentProfile.prn == student_id_or_prn) | 
        (StudentProfile.roll_no == student_id_or_prn)
    ).first()

    if not student:
        return jsonify({'status': 'failed', 'message': f'Student {student_id_or_prn} not found.'}), 404

    ac_class = student.academic_class
    conducted_sessions = LectureSession.query.filter_by(class_id=student.class_id).all()
    total_conducted = len(conducted_sessions)

    records = AttendanceRecord.query.filter_by(student_id=student.id).order_by(AttendanceRecord.timestamp.desc()).all()
    total_attended = len(records)
    overall_pct = round((total_attended / total_conducted * 100.0), 1) if total_conducted > 0 else 0.0

    # Subjects breakdown
    subjects = Subject.query.filter_by(department_id=ac_class.department_id, semester=ac_class.semester).all() if ac_class else []
    sub_stats = []
    for sub in subjects:
        sub_sess = [s for s in conducted_sessions if s.subject_id == sub.id]
        total_sub = len(sub_sess)
        sub_ids = [s.id for s in sub_sess]
        att_sub = sum(1 for r in records if r.session_id in sub_ids)
        sub_pct = round((att_sub / total_sub * 100.0), 1) if total_sub > 0 else 0.0
        sub_stats.append({
            'name': sub.name,
            'code': sub.code,
            'conducted': total_sub,
            'attended': att_sub,
            'percentage': sub_pct,
            'is_defaulter': sub_pct < 50.0
        })

    history = [
        {
            'session_id': r.session_id,
            'subject_name': r.session.subject.name if r.session and r.session.subject else 'Lecture',
            'subject_code': r.session.subject.code if r.session and r.session.subject else '',
            'teacher_name': r.session.teacher.user.full_name if r.session and r.session.teacher and r.session.teacher.user else 'Faculty',
            'timestamp': r.timestamp.strftime('%Y-%m-%d %I:%M:%S %p') if r.timestamp else '',
            'distance_meters': round(r.distance_meters, 2),
            'status': r.status
        }
        for r in records
    ]

    return jsonify({
        'status': 'success',
        'student': {
            'id': student.id,
            'prn': student.prn,
            'roll_no': student.roll_no,
            'full_name': student.user.full_name if student.user else '',
            'email': student.user.email if student.user else '',
            'class_name': ac_class.name if ac_class else '',
            'division': ac_class.division if ac_class else '',
            'total_conducted': total_conducted,
            'total_attended': total_attended,
            'percentage': overall_pct,
            'is_defaulter': overall_pct < 50.0
        },
        'subjects': sub_stats,
        'history': history
    }), 200

# -------------------------------------------------------------
# APPLICATION ENTRY POINT
# -------------------------------------------------------------
if __name__ == '__main__':
    seed_initial_data()
    print("[STARTUP] Attendio Smart Multi-College Attendance Platform running on http://0.0.0.0:5000")
    print("[ADMIN] College Admin Console: http://127.0.0.1:5000/admin")
    print("[PORTAL] Student Attendance Portal: http://127.0.0.1:5000/attend")
    app.run(host='0.0.0.0', port=5000, debug=False)