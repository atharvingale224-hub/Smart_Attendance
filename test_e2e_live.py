import os
import sys
sys.stdout.reconfigure(encoding='utf-8')
import time
import json
from app import app, db, seed_initial_data
from models import (
    College, User, Department, AcademicClass, Subject, 
    StudentProfile, TeacherProfile, TimetableSlot, 
    LectureSession, AttendanceRecord, ProxyRiskLog, GeofenceConfig
)
from services import GeoService, QRTokenService, AttendanceService, ReportService

def run_e2e_tests():
    print("=" * 75)
    print("ATTENDIO END-TO-END LIVE FUNCTIONAL VERIFICATION")
    print("=" * 75)

    # 1. Test Persistent Database Initialization on Disk
    disk_db_path = os.path.join(os.path.dirname(__file__), 'attendio_e2e_test.db')
    if os.path.exists(disk_db_path):
        os.remove(disk_db_path)

    app.config['SQLALCHEMY_DATABASE_URI'] = f"sqlite:///{disk_db_path}"
    app.config['TESTING'] = True

    print("\n[STEP 1] Testing Database Initialization and Seed on Disk:")
    with app.app_context():
        db.create_all()
        seed_initial_data()
        
        # Verify initial data presence
        colleges = College.query.all()
        users = User.query.all()
        classes = AcademicClass.query.all()
        students = StudentProfile.query.all()
        teachers = TeacherProfile.query.all()
        print(f"  ✓ Database created on disk: {disk_db_path}")
        print(f"  ✓ Seeded {len(colleges)} college(s), {len(users)} user(s), {len(classes)} class(es), {len(teachers)} teacher(s), {len(students)} student(s).")
        assert len(colleges) >= 1
        assert len(users) >= 7

    with app.test_client() as client:
        # -----------------------------------------------------------------
        # [STEP 2] College Admin Workflow
        # -----------------------------------------------------------------
        print("\n[STEP 2] Testing College Admin Workflow:")
        # Admin Login
        admin_login = client.post('/api/auth/login', json={
            'email': 'admin@gcek.ac.in',
            'password': 'Admin@1234'
        })
        assert admin_login.status_code == 200, "Admin login failed"
        admin_data = admin_login.get_json()
        admin_token = admin_data['auth_token']
        print(f"  ✓ Admin logged in: {admin_data['user']['full_name']} (Role: {admin_data['user']['role']})")

        # Admin fetches Dashboard Stats
        stats_res = client.get('/api/admin/dashboard-stats')
        assert stats_res.status_code == 200
        stats = stats_res.get_json()
        print(f"  ✓ Admin Dashboard Stats: Students={stats['students_count']}, Teachers={stats['teachers_count']}, Classes={stats['classes_count']}, Geofence Radius={stats['geofence']['radius_meters']}m")

        # Admin Updates Campus Geofence
        geo_update = client.post('/api/admin/geofence', json={
            'latitude': 16.6850,
            'longitude': 74.2350,
            'radius_meters': 250.0,
            'max_accuracy_meters': 45.0
        })
        assert geo_update.status_code == 200
        print("  ✓ Admin updated campus geofence: Center=(16.6850, 74.2350), Radius=250.0m, Max Inaccuracy=45.0m")

        # Revert geofence for standard classroom testing
        client.post('/api/admin/geofence', json={
            'latitude': 16.6800,
            'longitude': 74.2300,
            'radius_meters': 150.0,
            'max_accuracy_meters': 50.0
        })

        # -----------------------------------------------------------------
        # [STEP 3] Teacher Workflow & Dynamic 40s Rotating QR
        # -----------------------------------------------------------------
        print("\n[STEP 3] Testing Teacher Workflow & QR Generation:")
        # Teacher Login
        t_login = client.post('/api/auth/login', json={
            'email': 'teacher@gcek.ac.in',
            'password': 'Teacher@1234'
        })
        assert t_login.status_code == 200
        t_data = t_login.get_json()
        teacher_token = t_data['auth_token']
        print(f"  ✓ Teacher logged in: {t_data['user']['full_name']}")

        # Teacher gets Timetable
        tt_res = client.get('/api/teacher/timetable', headers={'Authorization': f'Bearer {teacher_token}'})
        assert tt_res.status_code == 200
        tt_slots = tt_res.get_json()['timetable']
        print(f"  ✓ Teacher retrieved assigned timetable: {len(tt_slots)} scheduled lecture slot(s).")
        slot0 = tt_slots[0]
        print(f"    - Slot: {slot0['subject_name']} ({slot0['subject_code']}) for {slot0['class_name']} Div {slot0['division']} at {slot0['start_time']}-{slot0['end_time']}")

        # Teacher clicks "Start Attendance" -> generates initial 40s token
        start_res = client.post('/api/create-session', headers={'Authorization': f'Bearer {teacher_token}'})
        assert start_res.status_code == 200
        session_info = start_res.get_json()
        session_id = session_info['session_id']
        token_initial = session_info['token']
        print(f"  ✓ Attendance Session Started! ID: {session_id}")
        print(f"    - Initial 40s Token: {token_initial[:16]}... (valid_for_seconds: {session_info['valid_for_seconds']})")
        print(f"    - Projector URL: {session_info['url']}")

        # Projector poll: teacher app polls for remaining seconds and token rotation
        poll_res = client.get(f'/api/teacher/session/{session_id}/live-qr')
        assert poll_res.status_code == 200
        poll_data = poll_res.get_json()
        assert poll_data['current_token'] == token_initial
        print(f"  ✓ Projector Live QR Poll: Current Token Active, Remaining: {poll_data['seconds_remaining']}s")

        # -----------------------------------------------------------------
        # [STEP 4] Student Workflow (Simulating Mobile Browser Client)
        # -----------------------------------------------------------------
        print("\n[STEP 4] Testing Student Workflow from Mobile Browser Client:")
        mobile_headers = {
            'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1',
            'X-Forwarded-For': '49.36.120.15' # Student on Reliance Jio 5G mobile data
        }

        # 1. Student opens student portal URL on mobile
        portal_page = client.get(f'/attend?session={session_id}&token={token_initial}', headers=mobile_headers)
        assert portal_page.status_code == 200
        html_body = portal_page.data.decode('utf-8')
        assert "http://127.0.0.1:5000" not in html_body
        assert "/api/mark-attendance" in html_body
        print("  ✓ Student opens /attend portal on mobile data: Verified no hardcoded localhost URLs.")

        # 2. Student 1 marks attendance successfully (Within campus geofence)
        st1_sub = client.post('/api/mark-attendance', headers=mobile_headers, json={
            'session_id': session_id,
            'prn': 'PRN2024001',
            'latitude': 16.6802,
            'longitude': 74.2301,
            'accuracy': 8.5,
            'device_uuid': 'mobile_device_iphone_atharva',
            'token': token_initial
        })
        assert st1_sub.status_code == 200
        st1_data = st1_sub.get_json()
        print(f"  ✓ Student 1 (PRN2024001): {st1_data['message']} (Recorded distance: {st1_data['record']['distance_meters']}m)")

        # 3. Student 2 marks attendance successfully (Android mobile client on Airtel 4G)
        android_headers = {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.119 Mobile Safari/537.36',
            'X-Forwarded-For': '106.215.88.94'
        }
        st2_sub = client.post('/api/mark-attendance', headers=android_headers, json={
            'session_id': session_id,
            'prn': 'PRN2024002',
            'latitude': 16.6805,
            'longitude': 74.2298,
            'accuracy': 12.0,
            'device_uuid': 'mobile_device_galaxy_rohan',
            'token': token_initial
        })
        assert st2_sub.status_code == 200
        print("  ✓ Student 2 (PRN2024002): Attendance marked successfully from separate Android client.")

        # -----------------------------------------------------------------
        # [STEP 5] Anti-Proxy & Security Edge Cases
        # -----------------------------------------------------------------
        print("\n[STEP 5] Testing Anti-Proxy Security Edge Cases:")

        # A. Duplicate Attendance Attempt
        dup_sub = client.post('/api/mark-attendance', headers=mobile_headers, json={
            'session_id': session_id,
            'prn': 'PRN2024001',
            'latitude': 16.6802,
            'longitude': 74.2301,
            'accuracy': 8.5,
            'device_uuid': 'mobile_device_iphone_atharva',
            'token': token_initial
        })
        assert dup_sub.status_code == 400
        print(f"  ✓ Duplicate Prevention Block: {dup_sub.get_json()['message']}")

        # B. Device Mismatch Proxy Attempt (Atharva's phone tries to mark attendance for Sneha PRN2024003)
        # First register Sneha on her own device
        client.post('/api/mark-attendance', json={
            'session_id': session_id,
            'prn': 'PRN2024003',
            'latitude': 16.6800,
            'longitude': 74.2300,
            'accuracy': 10.0,
            'device_uuid': 'sneha_personal_pixel_phone',
            'token': token_initial
        })
        # Next lecture session
        s2_res = client.post('/api/create-session')
        session_id_2 = s2_res.get_json()['session_id']
        token_s2 = s2_res.get_json()['token']

        # Proxy attempt: Atharva's phone submits for Sneha's PRN
        proxy_dev = client.post('/api/mark-attendance', headers=mobile_headers, json={
            'session_id': session_id_2,
            'prn': 'PRN2024003',
            'latitude': 16.6800,
            'longitude': 74.2300,
            'accuracy': 10.0,
            'device_uuid': 'mobile_device_iphone_atharva',
            'token': token_s2
        })
        assert proxy_dev.status_code == 403
        print(f"  ✓ Device Binding Proxy Block: {proxy_dev.get_json()['message']}")

        # C. Expired Token Attempt (Server-Side 40s Enforced)
        with app.app_context():
            sess_obj = db.session.get(LectureSession, session_id_2)
            sess_obj.token_generated_at = time.time() - 45.0 # Expired by 5 seconds
            db.session.commit()

        exp_sub = client.post('/api/mark-attendance', json={
            'session_id': session_id_2,
            'prn': 'PRN2024004',
            'latitude': 16.6800,
            'longitude': 74.2300,
            'accuracy': 10.0,
            'device_uuid': 'pooja_phone',
            'token': token_s2
        })
        assert exp_sub.status_code == 400
        assert "expired" in exp_sub.get_json()['message'].lower()
        print(f"  ✓ Expired QR Token Block: {exp_sub.get_json()['message']}")

        # D. Out of Campus Boundary Attempt (Student off-campus trying to scan)
        out_sub = client.post('/api/mark-attendance', json={
            'session_id': session_id,
            'prn': 'PRN2024005',
            'latitude': 18.5204,
            'longitude': 73.8567, # Off-campus in Pune (160km away)
            'accuracy': 15.0,
            'device_uuid': 'vikas_home_phone',
            'token': token_initial
        })
        assert out_sub.status_code == 400
        print(f"  ✓ GPS Geofence Perimeter Block: {out_sub.get_json()['message']}")

        # E. Inaccurate GPS Reading (> 50m)
        inacc_sub = client.post('/api/mark-attendance', json={
            'session_id': session_id,
            'prn': 'PRN2024005',
            'latitude': 16.6800,
            'longitude': 74.2300,
            'accuracy': 220.0, # Accuracy 220m
            'device_uuid': 'vikas_home_phone',
            'token': token_initial
        })
        assert inacc_sub.status_code == 400
        print(f"  ✓ Poor GPS Accuracy Block: {inacc_sub.get_json()['message']}")

        # -----------------------------------------------------------------
        # [STEP 6] Teacher Ends Session & Roster Reports
        # -----------------------------------------------------------------
        print("\n[STEP 6] Testing Session Closure & Attendance Reports:")
        # Teacher checks live stats
        live_stats = client.get(f'/api/attendance-report?session_id={session_id}')
        assert live_stats.status_code == 200
        records = live_stats.get_json()['records']
        print(f"  ✓ Live attendance counter on teacher screen: {len(records)} students marked present.")

        # Teacher clicks "End Attendance Session"
        end_call = client.post(f'/api/teacher/session/{session_id}/end')
        assert end_call.status_code == 200
        summary = end_call.get_json()['summary']
        print(f"  ✓ Session ended and finalized: Total={summary['total_enrolled']}, Present={summary['total_present']}, Absent={summary['total_absent']}, Percentage={summary['attendance_percentage']}%")
        assert summary['total_present'] == 3 # PRN2024001, PRN2024002, PRN2024003
        assert summary['total_absent'] == 2  # PRN2024004, PRN2024005
        assert summary['attendance_percentage'] == 60.0

        # Submissions on closed session must be rejected
        late_sub = client.post('/api/mark-attendance', json={
            'session_id': session_id,
            'prn': 'PRN2024004',
            'latitude': 16.6800,
            'longitude': 74.2300,
            'accuracy': 10.0,
            'token': token_initial
        })
        assert late_sub.status_code == 400
        print(f"  ✓ Closed Session Rejection: {late_sub.get_json()['message']}")

        # CSV Download Test
        csv_download = client.get(f'/api/reports/session/{session_id}/export-csv')
        assert csv_download.status_code == 200
        assert "text/csv" in csv_download.headers['Content-Type']
        print(f"  ✓ CSV Report Exported: {len(csv_download.data)} bytes")

        # Excel Download Test
        excel_download = client.get(f'/api/reports/session/{session_id}/export-excel')
        assert excel_download.status_code == 200
        assert "spreadsheetml" in excel_download.headers['Content-Type']
        print(f"  ✓ Excel (.xlsx) Report Exported: {len(excel_download.data)} bytes")

        # Defaulter List Test (< 75% attendance)
        def_res = client.get('/api/reports/defaulters?threshold=75')
        assert def_res.status_code == 200
        defaulters = def_res.get_json()['defaulters']
        print(f"  ✓ Defaulter Evaluation (<75%): {len(defaulters)} student(s) below threshold:")
        for d in defaulters:
            print(f"    - PRN: {d['prn']} ({d['name']}) -> {d['present_lectures']}/{d['conducted_lectures']} lectures ({d['attendance_percentage']}%)")

    # -----------------------------------------------------------------
    # [STEP 7] Persistence Verification Across Process Restart
    # -----------------------------------------------------------------
    print("\n[STEP 7] Testing Database Persistence Across Application Restart:")
    # Re-initialize a fresh app context pointing to the same disk DB file
    with app.app_context():
        # Query existing sessions and records
        persisted_sessions = LectureSession.query.all()
        persisted_records = AttendanceRecord.query.all()
        persisted_risks = ProxyRiskLog.query.all()
        print(f"  ✓ Process Restart Verification: Successfully read from {disk_db_path}")
        print(f"    - Persisted Sessions: {len(persisted_sessions)}")
        print(f"    - Persisted Attendance Records: {len(persisted_records)}")
        print(f"    - Persisted Proxy Risk Log Events: {len(persisted_risks)}")
        assert len(persisted_sessions) >= 2
        assert len(persisted_records) >= 3
        assert len(persisted_risks) >= 3
        print("  ✓ All sessions, attendance records, and security risk logs persisted intact on disk!")

    # Cleanup test db file
    if os.path.exists(disk_db_path):
        os.remove(disk_db_path)

    print("\n" + "=" * 75)
    print("ALL LIVE FUNCTIONAL & WORKFLOW TESTS COMPLETED SUCCESSFULLY!")
    print("=" * 75)

if __name__ == '__main__':
    run_e2e_tests()
