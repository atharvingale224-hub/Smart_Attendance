from models import db, College, AcademicClass, Department, Subject, User, TeacherProfile, TimetableSlot
from werkzeug.security import generate_password_hash

COURSES = [
    ("AI", "Artificial Intelligence", "CS501", "Mr. K. P. Nilje", "nilje@bvcoek.edu.in"),
    ("CA", "Computer Algorithm", "CS502", "Dr. S. B. Patil", "patil@bvcoek.edu.in"),
    ("JP", "Java Programming", "CS503", "Ms. A. B. Pawar", "pawar@bvcoek.edu.in"),
    ("OOMD", "Object Oriented Modeling & Design", "CS504", "Mr. V. A. Upadhye", "teacher@gcek.ac.in"),
    ("MDM-03", "Multi-disciplinary Minor - 03", "CS505", "Mrs. Nayan Patil", "nayan.patil@bvcoek.edu.in"),
    ("OE-03", "Open Elective - 03", "CS506", "Ms. S. M. Bagban", "bagban@bvcoek.edu.in"),
]

# (Day, Start, End, CourseCode, Room)
SCHEDULE_SLOTS = [
    # Monday
    ("Monday", "11:30", "12:30", "OOMD", "LH2"),
    ("Monday", "12:30", "13:30", "MDM-03", "LH2"),
    ("Monday", "14:15", "16:15", "MDM-03", "L5"),
    
    # Tuesday
    ("Tuesday", "09:15", "10:15", "JP", "LH3"),
    ("Tuesday", "10:15", "11:15", "OOMD", "LH3"),
    ("Tuesday", "11:30", "12:30", "CA", "L4"),
    ("Tuesday", "12:30", "13:30", "JP", "L1"),
    ("Tuesday", "14:15", "16:15", "MDM-03", "L6"),

    # Wednesday
    ("Wednesday", "09:15", "10:15", "OE-03", "LH2"),
    ("Wednesday", "10:15", "11:15", "CA", "LH2"),
    ("Wednesday", "11:30", "12:30", "AI", "LH2"),
    ("Wednesday", "12:30", "13:30", "MDM-03", "LH2"),
    ("Wednesday", "14:15", "16:15", "MDM-03", "L6"),

    # Thursday
    ("Thursday", "09:15", "11:15", "OOMD", "L5"),
    ("Thursday", "11:30", "13:30", "JP", "L8"),
    ("Thursday", "14:15", "16:15", "MDM-03", "L6"),

    # Friday
    ("Friday", "09:15", "10:15", "OE-03", "LH2"),
    ("Friday", "10:15", "11:15", "CA", "LH2"),
    ("Friday", "11:30", "12:30", "AI", "LH2"),
    ("Friday", "12:30", "13:30", "MDM-03", "LH2"),
    ("Friday", "14:15", "16:15", "OOMD", "L5"),

    # Saturday
    ("Saturday", "09:00", "09:55", "OOMD", "LH2"),
    ("Saturday", "09:55", "10:50", "JP", "LH2"),
    ("Saturday", "11:10", "12:05", "CA", "LH3"),
    ("Saturday", "12:05", "13:00", "AI", "LH3"),
]

class _NullContext:
    def __enter__(self): return self
    def __exit__(self, *args): pass

def run():
    default_teacher_pw = generate_password_hash("Teacher@1234")
    with _NullContext():
        college = College.query.filter_by(code='BVCOEK').first() or College.query.first()
        if not college:
            print("No college found. Run seed_77_students first.")
            return

        dept = Department.query.filter_by(college_id=college.id).first()
        ac_class = AcademicClass.query.filter_by(college_id=college.id).first()

        # 1. Setup Faculty & Subjects
        subject_map = {}
        teacher_map = {}

        for code, name, sub_code, fac_name, email in COURSES:
            # Teacher
            user = User.query.filter_by(email=email).first()
            if not user:
                user = User(
                    college_id=college.id,
                    email=email,
                    full_name=fac_name,
                    role="TEACHER"
                )
                user.password_hash = default_teacher_pw
                db.session.add(user)
                db.session.flush()

            designation = "Assistant Professor & Class Teacher" if ("Upadhye" in fac_name or code == "OOMD") else "Professor / Faculty"
            if not user.teacher_profile:
                t_prof = TeacherProfile(
                    user_id=user.id,
                    college_id=college.id,
                    department_id=dept.id,
                    employee_id=f"FAC-{code}",
                    designation=designation
                )
                db.session.add(t_prof)
                db.session.flush()
            else:
                t_prof = user.teacher_profile
                t_prof.designation = designation

            teacher_map[code] = t_prof

        # Ensure upadhye@bvcoek.edu.in exists as Class Teacher
        up_user = User.query.filter_by(email="upadhye@bvcoek.edu.in").first()
        if not up_user:
            up_user = User(
                college_id=college.id,
                email="upadhye@bvcoek.edu.in",
                full_name="Mr. V. A. Upadhye",
                role="TEACHER"
            )
            up_user.password_hash = default_teacher_pw
            db.session.add(up_user)
            db.session.flush()
            up_prof = TeacherProfile(
                user_id=up_user.id,
                college_id=college.id,
                department_id=dept.id,
                employee_id="FAC-OOMD-BVCOEK",
                designation="Assistant Professor & Class Teacher"
            )
            db.session.add(up_prof)
            db.session.flush()
        elif up_user.teacher_profile:
            up_user.teacher_profile.designation = "Assistant Professor & Class Teacher"

            # Subject
            sub = Subject.query.filter_by(college_id=college.id, name=name).first()
            if not sub:
                sub = Subject.query.filter_by(college_id=college.id, code=sub_code).first()
            if not sub:
                sub = Subject(
                    college_id=college.id,
                    department_id=dept.id,
                    name=name,
                    code=sub_code,
                    semester=5
                )
                db.session.add(sub)
                db.session.flush()
            else:
                sub.name = name
                sub.code = sub_code

            subject_map[code] = sub

        db.session.commit()

        # 2. Clear old timetable slots for clean sync
        TimetableSlot.query.filter_by(class_id=ac_class.id).delete()
        db.session.commit()

        # 3. Insert Timetable Slots
        added_slots = 0
        for day, start, end, code, room in SCHEDULE_SLOTS:
            slot = TimetableSlot(
                college_id=college.id,
                teacher_id=teacher_map[code].id,
                class_id=ac_class.id,
                subject_id=subject_map[code].id,
                day_of_week=day,
                start_time=start,
                end_time=end,
                room=room
            )
            db.session.add(slot)
            added_slots += 1

        db.session.commit()
        print(f"[SUCCESS] Uploaded {added_slots} Timetable Slots for {ac_class.name}!")
        print(f"Courses: {len(COURSES)} subjects mapped to respective faculty.")

if __name__ == '__main__':
    from app import app
    with app.app_context():
        run()
