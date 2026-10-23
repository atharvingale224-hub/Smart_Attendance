import uuid
from datetime import datetime, timezone, timedelta
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash

# Indian Standard Time (IST: UTC + 5:30)
IST = timezone(timedelta(hours=5, minutes=30))

def get_ist_now():
    return datetime.now(IST).replace(tzinfo=None)

db = SQLAlchemy()

def generate_uuid():
    return str(uuid.uuid4())

class College(db.Model):
    __tablename__ = 'colleges'
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    name = db.Column(db.String(200), nullable=False)
    code = db.Column(db.String(20), unique=True, nullable=False, index=True)
    domain = db.Column(db.String(100), nullable=True)
    is_verified = db.Column(db.Boolean, default=False)
    is_active = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    # Relationships
    geofence = db.relationship('GeofenceConfig', backref='college', uselist=False, cascade='all, delete-orphan')
    users = db.relationship('User', backref='college', cascade='all, delete-orphan')
    departments = db.relationship('Department', backref='college', cascade='all, delete-orphan')
    classes = db.relationship('AcademicClass', backref='college', cascade='all, delete-orphan')
    subjects = db.relationship('Subject', backref='college', cascade='all, delete-orphan')
    sessions = db.relationship('LectureSession', backref='college', cascade='all, delete-orphan')

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'code': self.code,
            'domain': self.domain,
            'is_verified': self.is_verified,
            'is_active': self.is_active,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'geofence': self.geofence.to_dict() if self.geofence else None
        }

class GeofenceConfig(db.Model):
    __tablename__ = 'geofence_configs'
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    college_id = db.Column(db.String(36), db.ForeignKey('colleges.id', ondelete='CASCADE'), unique=True, nullable=False)
    latitude = db.Column(db.Float, nullable=False, default=16.6800)
    longitude = db.Column(db.Float, nullable=False, default=74.2300)
    radius_meters = db.Column(db.Float, nullable=False, default=150.0)
    max_accuracy_meters = db.Column(db.Float, nullable=False, default=50.0)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'college_id': self.college_id,
            'latitude': self.latitude,
            'longitude': self.longitude,
            'radius_meters': self.radius_meters,
            'max_accuracy_meters': self.max_accuracy_meters,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }

class User(db.Model):
    __tablename__ = 'users'
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    college_id = db.Column(db.String(36), db.ForeignKey('colleges.id', ondelete='CASCADE'), nullable=True, index=True)
    email = db.Column(db.String(150), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    full_name = db.Column(db.String(150), nullable=False)
    role = db.Column(db.String(20), nullable=False) # 'SUPERADMIN', 'COLLEGE_ADMIN', 'TEACHER', 'STUDENT'
    phone = db.Column(db.String(20), nullable=True)
    is_active = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    # Profiles
    teacher_profile = db.relationship('TeacherProfile', backref='user', uselist=False, cascade='all, delete-orphan')
    student_profile = db.relationship('StudentProfile', backref='user', uselist=False, cascade='all, delete-orphan')

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

    def to_dict(self):
        data = {
            'id': self.id,
            'college_id': self.college_id,
            'email': self.email,
            'full_name': self.full_name,
            'role': self.role,
            'phone': self.phone,
            'is_active': self.is_active,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }
        if self.role == 'TEACHER' and self.teacher_profile:
            t_data = self.teacher_profile.to_dict()
            data['teacher_profile'] = t_data
            data['is_class_teacher'] = t_data.get('is_class_teacher', False)
        elif self.role == 'STUDENT' and self.student_profile:
            data['student_profile'] = self.student_profile.to_dict()
        return data

class Department(db.Model):
    __tablename__ = 'departments'
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    college_id = db.Column(db.String(36), db.ForeignKey('colleges.id', ondelete='CASCADE'), nullable=False, index=True)
    name = db.Column(db.String(100), nullable=False)
    code = db.Column(db.String(20), nullable=False)

    classes = db.relationship('AcademicClass', backref='department', cascade='all, delete-orphan')
    subjects = db.relationship('Subject', backref='department', cascade='all, delete-orphan')
    teachers = db.relationship('TeacherProfile', backref='department')

    __table_args__ = (
        db.UniqueConstraint('college_id', 'code', name='uq_college_dept_code'),
    )

    def to_dict(self):
        return {
            'id': self.id,
            'college_id': self.college_id,
            'name': self.name,
            'code': self.code
        }

class AcademicClass(db.Model):
    __tablename__ = 'academic_classes'
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    college_id = db.Column(db.String(36), db.ForeignKey('colleges.id', ondelete='CASCADE'), nullable=False, index=True)
    department_id = db.Column(db.String(36), db.ForeignKey('departments.id', ondelete='CASCADE'), nullable=False)
    name = db.Column(db.String(100), nullable=False) # e.g. "Third Year CSE"
    semester = db.Column(db.Integer, nullable=False) # e.g. 5
    division = db.Column(db.String(10), nullable=False) # e.g. "A"
    academic_year = db.Column(db.String(20), nullable=False, default="2026-2027")

    students = db.relationship('StudentProfile', backref='academic_class', cascade='all, delete-orphan')
    timetable_slots = db.relationship('TimetableSlot', backref='academic_class', cascade='all, delete-orphan')
    sessions = db.relationship('LectureSession', backref='academic_class')

    __table_args__ = (
        db.UniqueConstraint('department_id', 'semester', 'division', 'academic_year', name='uq_class_div_sem_year'),
    )

    def to_dict(self):
        return {
            'id': self.id,
            'college_id': self.college_id,
            'department_id': self.department_id,
            'department_name': self.department.name if self.department else None,
            'name': self.name,
            'semester': self.semester,
            'division': self.division,
            'academic_year': self.academic_year,
            'student_count': len(self.students) if self.students else 0
        }

class Subject(db.Model):
    __tablename__ = 'subjects'
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    college_id = db.Column(db.String(36), db.ForeignKey('colleges.id', ondelete='CASCADE'), nullable=False, index=True)
    department_id = db.Column(db.String(36), db.ForeignKey('departments.id', ondelete='CASCADE'), nullable=False)
    name = db.Column(db.String(150), nullable=False)
    code = db.Column(db.String(20), nullable=False)
    semester = db.Column(db.Integer, nullable=False)

    timetable_slots = db.relationship('TimetableSlot', backref='subject', cascade='all, delete-orphan')
    sessions = db.relationship('LectureSession', backref='subject')

    __table_args__ = (
        db.UniqueConstraint('college_id', 'code', name='uq_college_subject_code'),
    )

    def to_dict(self):
        return {
            'id': self.id,
            'college_id': self.college_id,
            'department_id': self.department_id,
            'name': self.name,
            'code': self.code,
            'semester': self.semester
        }

class StudentProfile(db.Model):
    __tablename__ = 'student_profiles'
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    user_id = db.Column(db.String(36), db.ForeignKey('users.id', ondelete='CASCADE'), unique=True, nullable=False)
    college_id = db.Column(db.String(36), db.ForeignKey('colleges.id', ondelete='CASCADE'), nullable=False, index=True)
    class_id = db.Column(db.String(36), db.ForeignKey('academic_classes.id', ondelete='CASCADE'), nullable=False)
    prn = db.Column(db.String(50), nullable=False, index=True)
    roll_no = db.Column(db.String(20), nullable=True)
    registered_device_uuid = db.Column(db.String(100), nullable=True)
    device_registered_at = db.Column(db.DateTime, nullable=True)

    attendance_records = db.relationship('AttendanceRecord', backref='student', cascade='all, delete-orphan')

    __table_args__ = (
        db.UniqueConstraint('college_id', 'prn', name='uq_college_prn'),
    )

    def to_dict(self):
        return {
            'id': self.id,
            'user_id': self.user_id,
            'college_id': self.college_id,
            'class_id': self.class_id,
            'class_name': self.academic_class.name if self.academic_class else None,
            'prn': self.prn,
            'roll_no': self.roll_no,
            'full_name': self.user.full_name if self.user else None,
            'email': self.user.email if self.user else None,
            'is_device_bound': bool(self.registered_device_uuid),
            'registered_device_uuid': self.registered_device_uuid
        }

class TeacherProfile(db.Model):
    __tablename__ = 'teacher_profiles'
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    user_id = db.Column(db.String(36), db.ForeignKey('users.id', ondelete='CASCADE'), unique=True, nullable=False)
    college_id = db.Column(db.String(36), db.ForeignKey('colleges.id', ondelete='CASCADE'), nullable=False, index=True)
    department_id = db.Column(db.String(36), db.ForeignKey('departments.id', ondelete='SET NULL'), nullable=True)
    employee_id = db.Column(db.String(50), nullable=True)
    designation = db.Column(db.String(100), default="Assistant Professor")

    timetable_slots = db.relationship('TimetableSlot', backref='teacher', cascade='all, delete-orphan')
    sessions = db.relationship('LectureSession', backref='teacher')

    def to_dict(self):
        email = self.user.email if self.user else ""
        is_ct = (
            email in ["teacher@gcek.ac.in", "upadhye@bvcoek.edu.in"] or 
            "Class Teacher" in (self.designation or "")
        )
        return {
            'id': self.id,
            'user_id': self.user_id,
            'college_id': self.college_id,
            'department_id': self.department_id,
            'department_name': self.department.name if self.department else None,
            'employee_id': self.employee_id,
            'designation': self.designation,
            'full_name': self.user.full_name if self.user else None,
            'email': email,
            'is_class_teacher': is_ct
        }

class TimetableSlot(db.Model):
    __tablename__ = 'timetable_slots'
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    college_id = db.Column(db.String(36), db.ForeignKey('colleges.id', ondelete='CASCADE'), nullable=False, index=True)
    teacher_id = db.Column(db.String(36), db.ForeignKey('teacher_profiles.id', ondelete='CASCADE'), nullable=False)
    class_id = db.Column(db.String(36), db.ForeignKey('academic_classes.id', ondelete='CASCADE'), nullable=False)
    subject_id = db.Column(db.String(36), db.ForeignKey('subjects.id', ondelete='CASCADE'), nullable=False)
    day_of_week = db.Column(db.String(20), nullable=False) # "Monday", "Tuesday", etc.
    start_time = db.Column(db.String(10), nullable=False) # "09:00"
    end_time = db.Column(db.String(10), nullable=False)   # "10:00"
    room = db.Column(db.String(50), nullable=True)

    sessions = db.relationship('LectureSession', backref='timetable_slot')

    def to_dict(self):
        return {
            'id': self.id,
            'college_id': self.college_id,
            'teacher_id': self.teacher_id,
            'teacher_name': self.teacher.user.full_name if self.teacher and self.teacher.user else None,
            'class_id': self.class_id,
            'class_name': self.academic_class.name if self.academic_class else None,
            'division': self.academic_class.division if self.academic_class else None,
            'subject_id': self.subject_id,
            'subject_name': self.subject.name if self.subject else None,
            'subject_code': self.subject.code if self.subject else None,
            'day_of_week': self.day_of_week,
            'start_time': self.start_time,
            'end_time': self.end_time,
            'room': self.room
        }

class LectureSession(db.Model):
    __tablename__ = 'lecture_sessions'
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    college_id = db.Column(db.String(36), db.ForeignKey('colleges.id', ondelete='CASCADE'), nullable=False, index=True)
    timetable_slot_id = db.Column(db.String(36), db.ForeignKey('timetable_slots.id', ondelete='SET NULL'), nullable=True)
    teacher_id = db.Column(db.String(36), db.ForeignKey('teacher_profiles.id', ondelete='CASCADE'), nullable=False)
    class_id = db.Column(db.String(36), db.ForeignKey('academic_classes.id', ondelete='CASCADE'), nullable=False)
    subject_id = db.Column(db.String(36), db.ForeignKey('subjects.id', ondelete='CASCADE'), nullable=False)
    status = db.Column(db.String(20), default='ACTIVE') # 'ACTIVE', 'CLOSED', 'CANCELLED'
    started_at = db.Column(db.DateTime, default=get_ist_now)
    closed_at = db.Column(db.DateTime, nullable=True)
    
    # Secure Dynamic Rotating Token
    current_token = db.Column(db.String(100), nullable=False)
    token_generated_at = db.Column(db.Float, nullable=False) # Unix epoch time
    token_sequence = db.Column(db.Integer, default=1)

    # Dynamic Teacher Phone Proximity Geofencing (Classroom 50-meter radius)
    teacher_lat = db.Column(db.Float, nullable=True) # Teacher's phone latitude at session creation
    teacher_lng = db.Column(db.Float, nullable=True) # Teacher's phone longitude at session creation
    proximity_radius_meters = db.Column(db.Float, default=50.0) # Strictly 50m radius around teacher

    attendance_records = db.relationship('AttendanceRecord', backref='session', cascade='all, delete-orphan')
    risk_logs = db.relationship('ProxyRiskLog', backref='session', cascade='all, delete-orphan')

    def to_dict(self):
        return {
            'id': self.id,
            'college_id': self.college_id,
            'timetable_slot_id': self.timetable_slot_id,
            'teacher_id': self.teacher_id,
            'teacher_name': self.teacher.user.full_name if self.teacher and self.teacher.user else None,
            'class_id': self.class_id,
            'class_name': self.academic_class.name if self.academic_class else None,
            'division': self.academic_class.division if self.academic_class else None,
            'subject_id': self.subject_id,
            'subject_name': self.subject.name if self.subject else None,
            'subject_code': self.subject.code if self.subject else None,
            'status': self.status,
            'started_at': self.started_at.isoformat() if self.started_at else None,
            'closed_at': self.closed_at.isoformat() if self.closed_at else None,
            'token_sequence': self.token_sequence,
            'teacher_lat': self.teacher_lat,
            'teacher_lng': self.teacher_lng,
            'proximity_radius_meters': self.proximity_radius_meters or 50.0,
            'attendance_count': len(self.attendance_records) if self.attendance_records else 0
        }

class AttendanceRecord(db.Model):
    __tablename__ = 'attendance_records'
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    college_id = db.Column(db.String(36), db.ForeignKey('colleges.id', ondelete='CASCADE'), nullable=False, index=True)
    session_id = db.Column(db.String(36), db.ForeignKey('lecture_sessions.id', ondelete='CASCADE'), nullable=False, index=True)
    student_id = db.Column(db.String(36), db.ForeignKey('student_profiles.id', ondelete='CASCADE'), nullable=False, index=True)
    prn = db.Column(db.String(50), nullable=False, index=True)
    timestamp = db.Column(db.DateTime, default=get_ist_now)
    distance_meters = db.Column(db.Float, nullable=False)
    accuracy_meters = db.Column(db.Float, nullable=False, default=10.0)
    status = db.Column(db.String(20), default='PRESENT') # 'PRESENT', 'EXCUSED'

    # STRICT DB UNIQUE CONSTRAINT: One attendance record per student per lecture session!
    __table_args__ = (
        db.UniqueConstraint('session_id', 'student_id', name='uq_session_student_attendance'),
    )

    def to_dict(self):
        ts_str = self.timestamp.strftime("%Y-%m-%d %I:%M:%S %p") if self.timestamp else None
        time_12h = self.timestamp.strftime("%I:%M %p") if self.timestamp else None
        return {
            'id': self.id,
            'college_id': self.college_id,
            'session_id': self.session_id,
            'student_id': self.student_id,
            'prn': self.prn,
            'student_name': self.student.user.full_name if self.student and self.student.user else None,
            'roll_no': self.student.roll_no if self.student else None,
            'timestamp': ts_str,
            'time_12h': time_12h,
            'distance_meters': round(self.distance_meters, 2),
            'accuracy_meters': round(self.accuracy_meters, 2),
            'status': self.status
        }

class ProxyRiskLog(db.Model):
    __tablename__ = 'proxy_risk_logs'
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    college_id = db.Column(db.String(36), db.ForeignKey('colleges.id', ondelete='CASCADE'), nullable=False, index=True)
    session_id = db.Column(db.String(36), db.ForeignKey('lecture_sessions.id', ondelete='CASCADE'), nullable=True)
    student_id = db.Column(db.String(36), db.ForeignKey('student_profiles.id', ondelete='SET NULL'), nullable=True)
    prn = db.Column(db.String(50), nullable=True)
    risk_type = db.Column(db.String(50), nullable=False) # 'EXPIRED_TOKEN', 'OUT_OF_BOUNDS', 'POOR_ACCURACY', 'DEVICE_MISMATCH', 'DUPLICATE_ATTEMPT', 'UNAUTHORIZED_ACCESS'
    details = db.Column(db.Text, nullable=False)
    ip_address = db.Column(db.String(50), nullable=True)
    user_agent = db.Column(db.String(255), nullable=True)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'college_id': self.college_id,
            'session_id': self.session_id,
            'prn': self.prn,
            'risk_type': self.risk_type,
            'details': self.details,
            'ip_address': self.ip_address,
            'timestamp': self.timestamp.strftime("%Y-%m-%d %H:%M:%S") if self.timestamp else None
        }
