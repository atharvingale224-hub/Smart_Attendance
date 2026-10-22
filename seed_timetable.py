import os
from app import app, db
from models import College, AcademicClass, Department, Subject, User, TeacherProfile, TimetableSlot

COURSES = [
    ("AI", "Artificial Intelligence", "CS501", "Mr. K. P. Nilje", "nilje@bvcoek.edu.in"),
    ("CA", "Computer Algorithm", "CS502", "Dr. S. B. Patil", "patil@bvcoek.edu.in"),
    ("JP", "Java Programming", "CS503", "Ms. A. B. Pawar", "pawar@bvcoek.edu.in"),
    ("OOMD", "Object Oriented Modeling & Design", "CS504", "Mr. V. A. Upadhye", "teacher@gcek.ac.in"),
    ("MDM-03", "Multi-disciplinary Minor - 03", "CS505", "Ms. M. P. Kulkarni", "kulkarni@bvcoek.edu.in"),
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

def run():
    with app.app_context():
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
                user.set_password("Teacher@1234")
                db.session.add(user)
                db.session.flush()

            if not user.teacher_profile:
                t_prof = TeacherProfile(
                    user_id=user.id,
                    college_id=college.id,
                    department_id=dept.id,
                    employee_id=f"FAC-{code}",
                    designation="Professor / Faculty"
                )
                db.session.add(t_prof)
                db.session.flush()
            else:
                t_prof = user.teacher_profile

            teacher_map[code] = t_prof

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
    run()
