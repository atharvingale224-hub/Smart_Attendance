import math
import time
import secrets
import io
import csv
from datetime import datetime
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

from models import db, College, GeofenceConfig, AcademicClass, StudentProfile, LectureSession, AttendanceRecord, ProxyRiskLog, get_ist_now

class GeoService:
    @staticmethod
    def calculate_distance(lat1, lon1, lat2, lon2):
        """Haversine distance formula between two GPS points in meters"""
        R = 6371000.0  # Earth radius in meters
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        delta_phi = math.radians(lat2 - lat1)
        delta_lambda = math.radians(lon2 - lon1)

        a = math.sin(delta_phi / 2.0)**2 + \
            math.cos(phi1) * math.cos(phi2) * \
            math.sin(delta_lambda / 2.0)**2

        c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
        return R * c

    @classmethod
    def validate_location(cls, geofence, student_lat, student_lng, accuracy):
        """
        Server-side GPS verification:
        1. Validate coordinates range
        2. Validate reported GPS accuracy (reject poor/mocked accuracy)
        3. Calculate distance from campus center
        4. Validate against configured geofence radius
        """
        if not (-90.0 <= student_lat <= 90.0) or not (-180.0 <= student_lng <= 180.0):
            return False, 0.0, "Invalid GPS latitude/longitude values received."
            
        if accuracy is not None and accuracy > geofence.max_accuracy_meters:
            return False, 0.0, f"GPS accuracy too poor ({round(accuracy, 1)}m). Must be within {geofence.max_accuracy_meters}m. Please move near a window or check location settings."

        distance = cls.calculate_distance(
            geofence.latitude, 
            geofence.longitude, 
            student_lat, 
            student_lng
        )

        if distance > geofence.radius_meters:
            return False, distance, f"Outside campus geofence boundary. Distance: {round(distance, 1)}m (Allowed: {geofence.radius_meters}m)."

        return True, distance, "Location verified within campus geofence."

class QRTokenService:
    @staticmethod
    def generate_token():
        """Generates a cryptographically secure random token (256-bit URL-safe)"""
        return secrets.token_urlsafe(32)

    @classmethod
    def get_or_rotate_token(cls, session, max_age_seconds=80):
        """
        If current token is older than max_age_seconds, generates a new rotating token.
        Returns (current_token, time_remaining_seconds)
        """
        now = time.time()
        elapsed = now - session.token_generated_at
        
        if elapsed >= max_age_seconds:
            session.current_token = cls.generate_token()
            session.token_generated_at = now
            session.token_sequence = (session.token_sequence or 0) + 1
            db.session.commit()
            elapsed = 0.0

        remaining = max(0.0, max_age_seconds - elapsed)
        return session.current_token, int(remaining)

    @classmethod
    def verify_token(cls, session, submitted_token, max_age_seconds=80):
        """
        Strict server-side token validation:
        1. Session must be ACTIVE
        2. Token string must match current token
        3. Server elapsed time must be <= max_age_seconds
        """
        if session.status != 'ACTIVE':
            return False, "Attendance session has already been closed."

        if session.current_token != submitted_token:
            return False, "Invalid or outdated QR token. Please scan the current rotating QR code on the projector."

        elapsed = time.time() - session.token_generated_at
        if elapsed > max_age_seconds:
            return False, f"QR code token expired ({round(elapsed, 1)}s elapsed, maximum {max_age_seconds}s). Please scan the freshly updated code."

        return True, "Token valid."

class AttendanceService:
    @staticmethod
    def mark_attendance(
        session_id, 
        prn, 
        latitude, 
        longitude, 
        accuracy=10.0, 
        device_uuid=None, 
        ip_address=None, 
        user_agent=None,
        submitted_token=None
    ):
        session = db.session.get(LectureSession, session_id)
        if not session:
            return {'status': 'failed', 'message': 'Attendance session not found.'}, 404

        if session.status != 'ACTIVE':
            ProxyRiskLog_entry = ProxyRiskLog(
                college_id=session.college_id,
                session_id=session.id,
                prn=prn,
                risk_type='UNAUTHORIZED_ACCESS',
                details=f"Attempted to mark attendance on closed session {session.id}",
                ip_address=ip_address,
                user_agent=user_agent
            )
            db.session.add(ProxyRiskLog_entry)
            db.session.commit()
            return {'status': 'failed', 'message': 'This attendance session has already been closed.'}, 400

        # Verify QR Token
        if submitted_token:
            token_valid, token_msg = QRTokenService.verify_token(session, submitted_token)
            if not token_valid:
                ProxyRiskLog_entry = ProxyRiskLog(
                    college_id=session.college_id,
                    session_id=session.id,
                    prn=prn,
                    risk_type='EXPIRED_TOKEN',
                    details=f"Token verification failed: {token_msg}",
                    ip_address=ip_address,
                    user_agent=user_agent
                )
                db.session.add(ProxyRiskLog_entry)
                db.session.commit()
                return {'status': 'failed', 'message': token_msg}, 400

        # Look up Student
        student = StudentProfile.query.filter_by(
            college_id=session.college_id, 
            prn=prn
        ).first()

        if not student:
            return {'status': 'failed', 'message': f'Student with PRN {prn} is not registered in this college.'}, 404

        # Validate Student belongs to the lecture's class
        if student.class_id != session.class_id:
            return {'status': 'failed', 'message': f'Student PRN {prn} does not belong to this class ({session.academic_class.name} Div {session.academic_class.division}).'}, 403

        # Device Binding & Auto-Sync
        if device_uuid:
            if not student.registered_device_uuid:
                # First-time registration of student's device
                student.registered_device_uuid = device_uuid
                student.device_registered_at = datetime.utcnow()
                db.session.commit()
            elif student.registered_device_uuid != device_uuid:
                # Seamlessly re-bind device while logging the switch in audit trail
                risk_entry = ProxyRiskLog(
                    college_id=session.college_id,
                    session_id=session.id,
                    student_id=student.id,
                    prn=prn,
                    risk_type='DEVICE_SWITCH',
                    details=f"Student device switched/updated from {student.registered_device_uuid[:8]}... to {device_uuid[:8]}...",
                    ip_address=ip_address,
                    user_agent=user_agent
                )
                db.session.add(risk_entry)
                student.registered_device_uuid = device_uuid
                student.device_registered_at = datetime.utcnow()
                db.session.commit()

        # Geofencing Validation
        college = db.session.get(College, session.college_id)
        geofence = college.geofence if college else None
        
        # Classroom Teacher Proximity Geofencing (Strictly 50-meter radius around teacher's phone)
        allowed_radius = session.proximity_radius_meters or 50.0
        if session.teacher_lat is not None and session.teacher_lng is not None:
            distance = GeoService.calculate_distance(
                session.teacher_lat,
                session.teacher_lng,
                latitude,
                longitude
            )
            if distance > allowed_radius:
                geo_msg = f"Outside classroom boundary! Distance from teacher's phone is {round(distance, 1)}m (Allowed: within {int(allowed_radius)}m)."
                risk_entry = ProxyRiskLog(
                    college_id=session.college_id,
                    session_id=session.id,
                    student_id=student.id,
                    prn=prn,
                    risk_type='OUT_OF_BOUNDS',
                    details=f"Classroom proximity violation: {geo_msg}",
                    ip_address=ip_address,
                    user_agent=user_agent
                )
                db.session.add(risk_entry)
                db.session.commit()
                return {'status': 'failed', 'message': geo_msg, 'distance_meters': round(distance, 1)}, 400
        else:
            # Fallback to campus geofence if teacher GPS was unavailable
            if not geofence:
                geofence = GeofenceConfig(
                    college_id=session.college_id,
                    latitude=16.6631,
                    longitude=74.2642,
                    radius_meters=50.0,
                    max_accuracy_meters=50.0
                )
            geo_valid, distance, geo_msg = GeoService.validate_location(
                geofence, 
                latitude, 
                longitude, 
                accuracy
            )
            if not geo_valid:
                risk_entry = ProxyRiskLog(
                    college_id=session.college_id,
                    session_id=session.id,
                    student_id=student.id,
                    prn=prn,
                    risk_type='OUT_OF_BOUNDS',
                    details=f"Geofence violation: {geo_msg}",
                    ip_address=ip_address,
                    user_agent=user_agent
                )
                db.session.add(risk_entry)
                db.session.commit()
                return {'status': 'failed', 'message': geo_msg}, 400

        # Duplicate Attendance Check
        existing_record = AttendanceRecord.query.filter_by(
            session_id=session.id, 
            student_id=student.id
        ).first()

        if existing_record:
            risk_entry = ProxyRiskLog(
                college_id=session.college_id,
                session_id=session.id,
                student_id=student.id,
                prn=prn,
                risk_type='DUPLICATE_ATTEMPT',
                details=f"Duplicate attendance submission attempt by student PRN {prn}",
                ip_address=ip_address,
                user_agent=user_agent
            )
            db.session.add(risk_entry)
            db.session.commit()
            return {'status': 'failed', 'message': f'Attendance has already been marked for PRN {prn} in this lecture!'}, 400

        # Atomic Transaction Attendance Creation
        try:
            record = AttendanceRecord(
                college_id=session.college_id,
                session_id=session.id,
                student_id=student.id,
                prn=student.prn,
                distance_meters=distance,
                accuracy_meters=accuracy or 10.0,
                status='PRESENT',
                timestamp=get_ist_now()
            )
            db.session.add(record)
            db.session.commit()
            
            return {
                'status': 'success',
                'message': f'Attendance successfully marked for {student.user.full_name} (PRN: {prn})!',
                'subject_name': session.subject.name if session.subject else 'Class Lecture',
                'subject_code': session.subject.code if session.subject else '',
                'teacher_name': session.teacher.user.full_name if session.teacher and session.teacher.user else 'Faculty',
                'room': session.timetable_slot.room if session.timetable_slot and session.timetable_slot.room else 'Classroom',
                'timestamp': record.timestamp.strftime('%d %b %Y, %I:%M %p'),
                'distance_meters': round(distance, 1),
                'allowed_radius_meters': int(allowed_radius),
                'record': record.to_dict()
            }, 200
        except Exception as e:
            db.session.rollback()
            return {'status': 'failed', 'message': f'Failed to record attendance: {str(e)}'}, 500

class ReportService:
    @staticmethod
    def get_session_attendance(session_id):
        session = db.session.get(LectureSession, session_id)
        if not session:
            return None

        # All enrolled students in class
        enrolled_students = StudentProfile.query.filter_by(class_id=session.class_id).all()
        attendance_records = AttendanceRecord.query.filter_by(session_id=session_id).all()
        
        present_student_ids = {r.student_id for r in attendance_records}
        
        present_list = [r.to_dict() for r in attendance_records]
        absent_list = [
            s.to_dict() for s in enrolled_students 
            if s.id not in present_student_ids
        ]
        
        total_enrolled = len(enrolled_students)
        total_present = len(present_list)
        percentage = round((total_present / total_enrolled * 100.0), 2) if total_enrolled > 0 else 0.0

        return {
            'session': session.to_dict(),
            'total_enrolled': total_enrolled,
            'total_present': total_present,
            'total_absent': len(absent_list),
            'attendance_percentage': percentage,
            'present_students': present_list,
            'absent_students': absent_list
        }

    @staticmethod
    def get_defaulter_list(class_id, threshold_percentage=75.0):
        students = StudentProfile.query.filter_by(class_id=class_id).all()
        # All conducted sessions for this class
        conducted_sessions = LectureSession.query.filter_by(class_id=class_id, status='CLOSED').all()
        total_conducted = len(conducted_sessions)
        
        if total_conducted == 0:
            return {
                'total_conducted_lectures': 0,
                'threshold_percentage': threshold_percentage,
                'defaulters': []
            }

        defaulters = []
        for student in students:
            present_count = AttendanceRecord.query.filter(
                AttendanceRecord.student_id == student.id,
                AttendanceRecord.session_id.in_([s.id for s in conducted_sessions])
            ).count()

            percentage = round((present_count / total_conducted * 100.0), 2)
            if percentage < threshold_percentage:
                defaulters.append({
                    'student_id': student.id,
                    'prn': student.prn,
                    'roll_no': student.roll_no,
                    'name': student.user.full_name if student.user else None,
                    'email': student.user.email if student.user else None,
                    'present_lectures': present_count,
                    'conducted_lectures': total_conducted,
                    'attendance_percentage': percentage
                })

        return {
            'total_conducted_lectures': total_conducted,
            'threshold_percentage': threshold_percentage,
            'defaulters': defaulters
        }

    @staticmethod
    def export_session_csv(session_id):
        data = ReportService.get_session_attendance(session_id)
        if not data:
            return None
            
        output = io.StringIO()
        writer = csv.writer(output)
        
        writer.writerow(["ATTENDIO ATTENDANCE REPORT"])
        writer.writerow(["Session ID", data['session']['id']])
        writer.writerow(["Subject", f"{data['session']['subject_name']} ({data['session']['subject_code']})"])
        writer.writerow(["Class", f"{data['session']['class_name']} Div {data['session']['division']}"])
        writer.writerow(["Teacher", data['session']['teacher_name']])
        writer.writerow(["Started At", data['session']['started_at']])
        writer.writerow(["Total Students", data['total_enrolled']])
        writer.writerow(["Present Count", data['total_present']])
        writer.writerow(["Percentage", f"{data['attendance_percentage']}%"])
        writer.writerow([])
        writer.writerow(["Status", "PRN", "Roll No", "Student Name", "Time", "Distance (m)", "Accuracy (m)"])
        
        for p in data['present_students']:
            writer.writerow(["PRESENT", p['prn'], p.get('roll_no', ''), p.get('student_name', ''), p['timestamp'], p['distance_meters'], p['accuracy_meters']])
            
        for a in data['absent_students']:
            writer.writerow(["ABSENT", a['prn'], a.get('roll_no', ''), a.get('full_name', ''), "-", "-", "-"])
            
        return output.getvalue()

    @staticmethod
    def export_session_excel(session_id):
        data = ReportService.get_session_attendance(session_id)
        if not data:
            return None
            
        wb = Workbook()
        ws = wb.active
        ws.title = "Lecture Attendance"
        
        header_fill = PatternFill(start_color="312E81", end_color="312E81", fill_type="solid")
        header_font = Font(name="Calibri", size=11, bold=True, color="FFFFFF")
        
        green_fill = PatternFill(start_color="DCFCE7", end_color="DCFCE7", fill_type="solid")
        green_font = Font(name="Calibri", size=10, bold=True, color="166534")
        red_fill = PatternFill(start_color="FEE2E2", end_color="FEE2E2", fill_type="solid")
        red_font = Font(name="Calibri", size=10, bold=True, color="991B1B")

        title_font = Font(name="Calibri", size=14, bold=True, color="1E1B4B")
        sub_font = Font(name="Calibri", size=11, bold=True, color="4338CA")

        ws.append(["BHARATI VIDYAPEETH COLLEGE OF ENGINEERING KOLHAPUR"])
        ws.append([f"Lecture: {data['session']['subject_name']} ({data['session']['subject_code']}) | Class: {data['session']['class_name']} Div {data['session']['division']}"])
        ws.append([f"Faculty: {data['session']['teacher_name']} | Date & Time: {data['session'].get('started_at_ist') or data['session']['started_at']} IST"])
        ws.append([f"Total Enrolled: {data['total_enrolled']} | Present: {data['total_present']} | Absent: {data['total_absent']} | Attendance: {data['attendance_percentage']}%"])
        ws.append([])

        ws.cell(row=1, column=1).font = title_font
        ws.cell(row=2, column=1).font = sub_font
        ws.cell(row=3, column=1).font = sub_font
        ws.cell(row=4, column=1).font = Font(name="Calibri", size=11, bold=True, color="166534")
        
        table_headers = ["Status", "Roll No", "PRN", "Student Full Name", "Scan Time (IST)", "GPS Distance (m)", "Accuracy (m)"]
        ws.append(table_headers)
        
        header_row = ws.max_row
        for col_num in range(1, len(table_headers) + 1):
            cell = ws.cell(row=header_row, column=col_num)
            cell.fill = header_fill
            cell.font = header_font
            cell.alignment = Alignment(horizontal="center", vertical="center")
            
        for p in data['present_students']:
            ws.append(["PRESENT", p.get('roll_no', '-'), p['prn'], p.get('student_name', ''), p.get('timestamp', ''), f"{p.get('distance_meters', 0)} m", f"±{p.get('accuracy_meters', 10)} m"])
            curr = ws.max_row
            ws.cell(row=curr, column=1).fill = green_fill
            ws.cell(row=curr, column=1).font = green_font
            
        for a in data['absent_students']:
            ws.append(["ABSENT", a.get('roll_no', '-'), a['prn'], a.get('full_name', ''), "-", "-", "-"])
            curr = ws.max_row
            ws.cell(row=curr, column=1).fill = red_fill
            ws.cell(row=curr, column=1).font = red_font

        for col in ws.columns:
            max_len = max(len(str(cell.value or '')) for cell in col)
            ws.column_dimensions[col[0].column_letter].width = max(max_len + 3, 12)
            
        output = io.BytesIO()
        wb.save(output)
        output.seek(0)
        return output.getvalue()

    @staticmethod
    def export_master_excel(class_id=None):
        college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
        college_id = college.id if college else None

        if not class_id:
            ac_class = AcademicClass.query.filter_by(college_id=college_id).first()
        else:
            ac_class = db.session.get(AcademicClass, class_id)

        if not ac_class:
            return None

        from models import Subject
        subjects = Subject.query.filter_by(department_id=ac_class.department_id, semester=ac_class.semester).all()
        if not subjects:
            subjects = Subject.query.filter_by(college_id=college_id).all()

        conducted_sessions = LectureSession.query.filter_by(class_id=ac_class.id).order_by(LectureSession.started_at.desc()).all()
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

        wb = Workbook()

        # ==========================================
        # SHEET 1: Master Cumulative Attendance Sheet
        # ==========================================
        ws1 = wb.active
        ws1.title = "Master Attendance Sheet"

        title_font = Font(name="Calibri", size=15, bold=True, color="1E1B4B")
        sub_font = Font(name="Calibri", size=11, bold=True, color="4338CA")
        info_font = Font(name="Calibri", size=10, italic=True, color="64748B")
        header_font = Font(name="Calibri", size=11, bold=True, color="FFFFFF")
        header_fill = PatternFill(start_color="312E81", end_color="312E81", fill_type="solid")
        
        green_fill = PatternFill(start_color="DCFCE7", end_color="DCFCE7", fill_type="solid")
        green_font = Font(name="Calibri", size=10, bold=True, color="166534")
        red_fill = PatternFill(start_color="FEE2E2", end_color="FEE2E2", fill_type="solid")
        red_font = Font(name="Calibri", size=10, bold=True, color="991B1B")

        now_ist = get_ist_now().strftime("%Y-%m-%d %I:%M %p")
        ws1.append(["BHARATI VIDYAPEETH COLLEGE OF ENGINEERING KOLHAPUR"])
        ws1.append([f"Department of Computer Science & Engineering | {ac_class.name} (Div-{ac_class.division})"])
        ws1.append(["MASTER CUMULATIVE ATTENDANCE LEDGER & DEFAULTER ANALYSIS"])
        ws1.append([f"Report Generated: {now_ist} IST | Defaulter Rule: Attendance strictly below 50.0%"])
        ws1.append([])

        ws1.cell(row=1, column=1).font = title_font
        ws1.cell(row=2, column=1).font = sub_font
        ws1.cell(row=3, column=1).font = sub_font
        ws1.cell(row=4, column=1).font = info_font

        headers = ["Sr", "Roll No", "PRN", "Student Full Name"]
        for sub in subjects:
            headers.append(f"{sub.code} ({sub.name[:12]})")
        headers.extend(["Total Attended", "Total Conducted", "Attendance %", "Defaulter Status (<50%)"])

        ws1.append(headers)
        h_row = ws1.max_row
        for col_idx in range(1, len(headers) + 1):
            c = ws1.cell(row=h_row, column=col_idx)
            c.fill = header_fill
            c.font = header_font
            c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)

        defaulters_list = []

        for idx, st in enumerate(students, 1):
            records = AttendanceRecord.query.filter_by(student_id=st.id).all()
            attended_session_ids = set(r.session_id for r in records)
            total_att = len(attended_session_ids)
            pct = round((total_att / total_conducted * 100.0), 1) if total_conducted > 0 else 0.0
            is_defaulter = pct < 50.0

            row_data = [
                idx,
                st.roll_no or "-",
                st.prn,
                st.user.full_name if st.user else "Student"
            ]

            for sub in subjects:
                sub_sess = subject_sessions.get(sub.id, [])
                sub_conducted = len(sub_sess)
                sub_attended = len(attended_session_ids.intersection(sub_sess))
                sub_pct = round((sub_attended / sub_conducted * 100.0), 0) if sub_conducted > 0 else 0
                row_data.append(f"{sub_attended}/{sub_conducted} ({int(sub_pct)}%)")

            row_data.extend([
                total_att,
                total_conducted,
                f"{pct}%",
                "DEFAULTER" if is_defaulter else "GOOD STANDING"
            ])

            ws1.append(row_data)
            curr_row = ws1.max_row

            pct_cell = ws1.cell(row=curr_row, column=len(headers) - 1)
            status_cell = ws1.cell(row=curr_row, column=len(headers))
            
            if is_defaulter:
                pct_cell.fill = red_fill
                pct_cell.font = red_font
                status_cell.fill = red_fill
                status_cell.font = red_font
                defaulters_list.append({
                    'roll_no': st.roll_no,
                    'prn': st.prn,
                    'name': st.user.full_name if st.user else "Student",
                    'total_att': total_att,
                    'total_conducted': total_conducted,
                    'pct': pct
                })
            else:
                pct_cell.fill = green_fill
                pct_cell.font = green_font
                status_cell.fill = green_fill
                status_cell.font = green_font

        for col in ws1.columns:
            max_len = max(len(str(cell.value or '')) for cell in col)
            ws1.column_dimensions[col[0].column_letter].width = max(max_len + 3, 11)

        # ==========================================
        # SHEET 2: Defaulters Notice List (< 50%)
        # ==========================================
        ws2 = wb.create_sheet(title="Defaulters Notice (<50%)")
        ws2.append(["OFFICIAL NOTICE: ATTENDANCE DEFAULTERS LIST (BELOW 50%)"])
        ws2.append([f"College: {college.name} | Class: {ac_class.name} (Div-{ac_class.division})"])
        ws2.append([f"As on: {now_ist} IST | Total Defaulters: {len(defaulters_list)} of {len(students)} Students"])
        ws2.append([])

        ws2.cell(row=1, column=1).font = Font(name="Calibri", size=14, bold=True, color="991B1B")
        ws2.cell(row=2, column=1).font = sub_font
        ws2.cell(row=3, column=1).font = Font(name="Calibri", size=11, bold=True, color="991B1B")

        d_headers = ["Sr", "Roll No", "PRN", "Student Full Name", "Lectures Attended", "Total Conducted", "Attendance %", "Defaulter Action"]
        ws2.append(d_headers)
        d_h_row = ws2.max_row
        d_fill = PatternFill(start_color="991B1B", end_color="991B1B", fill_type="solid")
        for col_idx in range(1, len(d_headers) + 1):
            c = ws2.cell(row=d_h_row, column=col_idx)
            c.fill = d_fill
            c.font = header_font
            c.alignment = Alignment(horizontal="center")

        for idx, d in enumerate(defaulters_list, 1):
            ws2.append([
                idx,
                d['roll_no'],
                d['prn'],
                d['name'],
                d['total_att'],
                d['total_conducted'],
                f"{d['pct']}%",
                "Strict Warning / Parent Call Required"
            ])
            r_idx = ws2.max_row
            ws2.cell(row=r_idx, column=7).fill = red_fill
            ws2.cell(row=r_idx, column=7).font = red_font

        ws2.append([])
        ws2.append(["Class Teacher Signature: _____________________", "", "", "HOD / Principal Signature: _____________________"])

        for col in ws2.columns:
            max_len = max(len(str(cell.value or '')) for cell in col)
            ws2.column_dimensions[col[0].column_letter].width = max(max_len + 3, 12)

        # ==========================================
        # SHEET 3: Chronological Lecture-by-Lecture Log
        # ==========================================
        ws3 = wb.create_sheet(title="Daily Lecture Log")
        ws3.append(["CHRONOLOGICAL LECTURE LOG & ATTENDANCE SUMMARY"])
        ws3.append([f"Class: {ac_class.name} Div-{ac_class.division}"])
        ws3.append([])

        log_headers = ["Sr", "Date & IST Time", "Subject", "Course Code", "Faculty Name", "Room", "Enrolled", "Present", "Absent", "Attendance %", "Status"]
        ws3.append(log_headers)
        l_h_row = ws3.max_row
        l_fill = PatternFill(start_color="4338CA", end_color="4338CA", fill_type="solid")
        for col_idx in range(1, len(log_headers) + 1):
            c = ws3.cell(row=l_h_row, column=col_idx)
            c.fill = l_fill
            c.font = header_font
            c.alignment = Alignment(horizontal="center")

        total_enrolled = len(students)
        for idx, sess in enumerate(conducted_sessions, 1):
            present_cnt = len(sess.attendance_records) if sess.attendance_records else 0
            absent_cnt = max(0, total_enrolled - present_cnt)
            pct = round((present_cnt / total_enrolled * 100.0), 1) if total_enrolled > 0 else 0.0
            time_str = sess.started_at.strftime("%Y-%m-%d %I:%M %p") if sess.started_at else "-"

            ws3.append([
                idx,
                time_str,
                sess.subject.name if sess.subject else "-",
                sess.subject.code if sess.subject else "-",
                sess.teacher.user.full_name if sess.teacher and sess.teacher.user else "-",
                "LH2",
                total_enrolled,
                present_cnt,
                absent_cnt,
                f"{pct}%",
                sess.status
            ])

        for col in ws3.columns:
            max_len = max(len(str(cell.value or '')) for cell in col)
            ws3.column_dimensions[col[0].column_letter].width = max(max_len + 3, 12)

        output = io.BytesIO()
        wb.save(output)
        output.seek(0)
        return output.getvalue()
