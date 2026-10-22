import os
import sys
from app import app, db
from models import College, GeofenceConfig, User, Department, AcademicClass, Subject, StudentProfile, TeacherProfile

STUDENTS_DATA = [
    (1, "CSTYA1", "2024071601", "BAGWAN AARIZ SAMEER", "A1"),
    (2, "CSTYA2", "2024071602", "BAMANE TRUPTI PRAKASH", "A1"),
    (3, "CSTYA3", "2024071603", "BHARATE SHAILESH DATTATRAY", "A1"),
    (4, "CSTYA4", "2024071604", "BHIOGADE RAJAT SIDDHARTH", "A1"),
    (5, "CSTYA5", "2024071605", "BHOITE ISHWARI SANTOSH", "A1"),
    (6, "CSTYA6", "2024071606", "BHOJANE PAYAL SACHIN", "A1"),
    (7, "CSTYA7", "2024071607", "BODHALE MAHESH BABASAHEB", "A1"),
    (8, "CSTYA8", "2024071608", "BOGARE ADITYA VINAYAK", "A1"),
    (9, "CSTYA9", "2024071609", "BUDAKE SUJAY SANJAY", "A1"),
    (10, "CSTYA10", "2024071610", "CHAVAN SARVESH NARAYAN", "A1"),
    (11, "CSTYA11", "2024071611", "CHOUGULE ARJUN LAVOO", "A1"),
    (12, "CSTYA12", "2024071612", "DALVI GAURAV ASHOK", "A1"),
    (13, "CSTYA13", "2024071613", "DAWANGAVE PRATHAMESH DATTA", "A1"),
    (14, "CSTYA14", "2024071614", "DESAI DHANASHRI MAHADEV", "A1"),
    (15, "CSTYA15", "2024071615", "DESAI SALMA SIRAJ", "A1"),
    (16, "CSTYA16", "2024071616", "GAIKWAD SANIYA VAIBHAV", "A1"),
    (17, "CSTYA17", "2024071617", "GAJARE ROHIT SAKHARAM", "A1"),
    (18, "CSTYA18", "2024071618", "GHATAGE TRUPTI DHANAJI", "A1"),
    (19, "CSTYA19", "2024071619", "GIRI RAJENDRA PUNDLIK", "A1"),
    (20, "CSTYA20", "2024071620", "GOSAWI SAHIL SURAJ", "A1"),
    (21, "CSTYA21", "2024071621", "GUJAR RIYA SANTOSH", "A2"),
    (22, "CSTYA22", "2024071622", "GURAV ANUJA PRAMOD", "A2"),
    (23, "CSTYA23", "2024071623", "HALGARE SUDARSHAN GUNWANT", "A2"),
    (24, "CSTYA24", "2024071624", "HALKARNIKAR OMKAR CHARUDATT", "A2"),
    (25, "CSTYA25", "2024071625", "HETKALE SNEHA LAHUKESH", "A2"),
    (26, "CSTYA26", "2024071626", "HORTIKAR PRUTHVI RAVI", "A2"),
    (27, "CSTYA27", "2024071627", "INGALE ATHARV ADHIKRAO", "A2"),
    (28, "CSTYA28", "2024071628", "JADHAV ADITYA MAHADEV", "A2"),
    (29, "CSTYA29", "2024071629", "JADHAV PRAJWAL PRAVIN", "A2"),
    (30, "CSTYA30", "2024071630", "JADHAV PRANISH SAYAJI", "A2"),
    (31, "CSTYA31", "2024071631", "JADHAV PREM POPAT", "A2"),
    (32, "CSTYA32", "2024071632", "JADHAV SUJAL ANIL", "A2"),
    (33, "CSTYA33", "2024071633", "JADHAV VINITA VITTHAL", "A2"),
    (34, "CSTYA34", "2024071634", "JAGTAP VEDANTI SATISH", "A2"),
    (35, "CSTYA35", "2024071635", "KADAM NIRGUN SANJAY", "A2"),
    (36, "CSTYA36", "2024071636", "KADAM OMKAR ARJUN", "A2"),
    (37, "CSTYA37", "2024071637", "KADAM OMKAR PRAKASH", "A2"),
    (38, "CSTYA38", "2024071638", "KAMBLE AVISHKAR ANIL", "A2"),
    (39, "CSTYA39", "2024071639", "KAMBLE JAYESH PRAKASH", "A3"),
    (40, "CSTYA40", "2024071640", "KAMBLE KARINA MARUTI", "A3"),
    (41, "CSTYA41", "2024071641", "KAMBLE MAYURI GANGADHAR", "A3"),
    (42, "CSTYA42", "2024071642", "KANDE SHRIKRUSHNA RAMESHWAR", "A3"),
    (43, "CSTYA43", "2024071643", "KASHID VAISHNAVI RAVSAHEB", "A3"),
    (44, "CSTYA44", "2024071644", "KHARADE RASIKA", "A3"),
    (45, "CSTYA45", "2024071645", "KHARAT PRANAV BAPUSO", "A3"),
    (46, "CSTYA46", "2024071646", "KHETAL PRATIKSHA PRAKASH", "A3"),
    (47, "CSTYA47", "2024071647", "KHOCHIKAR ARMISH SIRAJAHAMD", "A3"),
    (48, "CSTYA48", "2024071648", "KHOT ANAND RAJU", "A3"),
    (49, "CSTYA49", "2024071649", "KHUTALE ANUSHKA UTTAM", "A3"),
    (50, "CSTYA50", "2024071650", "KODALKAR OMKAR DHANAJI", "A3"),
    (51, "CSTYA51", "2024071651", "KOLHE SHWETA GANESH", "A3"),
    (52, "CSTYA52", "2024071652", "KOLI OMKAR RAJARAM", "A3"),
    (53, "CSTYA53", "2024071653", "KULKARNI MANTHAN PREMANAND", "A3"),
    (54, "CSTYA54", "2024071654", "KUMBHAR PARTH SANJAY", "A3"),
    (55, "CSTYA55", "2024071655", "KUMBHAR SHREE SURESH", "A3"),
    (56, "CSTYA56", "2024071656", "LANDAGE SUHAS SUNIL", "A3"),
    (57, "CSTYA57", "2024071657", "LOKHANDE SUDARSHAN DATTARAO", "A3"),
    (58, "CSTYA58", "2024071658", "MADANE PRANJALI PRADIP", "A3"),
    (59, "CSTYA59", "2024071659", "MADANE SHREYASH AJIT", "A4"),
    (60, "CSTYA60", "2024071660", "MANE AMRUTA ARJUN", "A4"),
    (61, "CSTYA61", "2024071661", "MANE SAMRUDDHI SATISH", "A4"),
    (62, "CSTYA62", "2024071662", "MANE SHRADDHA MADHUKAR", "A4"),
    (63, "CSTYA63", "2024071663", "MATOLE SONALI SHIVSHARAN", "A4"),
    (64, "CSTYA64", "2024071664", "KARANDE PRUTHVIRAJ SUHAS", "A4"),
    (65, "CSTYA65", "2024071665", "RAUT SHREYASH SUBHASHRAO", "A4"),
    (66, "CSTYA66", "2024071666", "ZODAGE PRATHMESH CHANDRASEN", "A4"),
    (67, "CSTYA67", "2024071667", "BIRAJDAR VAISHNAVI SIDDHARAM", "A4"),
    (68, "CSTYA68", "2024071668", "CHOUGULE MANASWI RAHUL", "A4"),
    (69, "CSTYA69", "2024071669", "DESAI KOMAL VISHNU", "A4"),
    (70, "CSTYA70", "2024071670", "DEVKATE PRADNYA BANDU", "A4"),
    (71, "CSTYA71", "2024071671", "FARAKATE SWADESH PRAKASH", "A4"),
    (72, "CSTYA72", "2024071672", "GAIKWAD PRATIKSHA VINOD", "A4"),
    (73, "CSTYA73", "2024071673", "GOSAVI GAURI BHARAT", "A4"),
    (74, "CSTYA74", "2024071674", "GOVEKAR SANIYA VASUDEV", "A4"),
    (75, "CSTYA75", "2024071675", "JADHAV SAKSHI PRAKASH", "A4"),
    (76, "CSTYA76", "2024071676", "JATHAR SHWETA SANJAY", "A4"),
    (77, "CSTYA77", "2024071677", "KAMBLE AISHWARYA PRASHANT", "A4"),
]

def run():
    with app.app_context():
        # Find college or create
        colleges = College.query.all()
        if not colleges:
            college = College(
                name="Bharati Vidyapeeth's College of Engineering Kolhapur",
                code="BVCOEK",
                domain="coekolhapur.bharatividyapeeth.edu",
                is_verified=True,
                is_active=True
            )
            db.session.add(college)
            db.session.flush()
            colleges = [college]
        else:
            for c in colleges:
                c.name = "Bharati Vidyapeeth's College of Engineering Kolhapur"
                c.code = "BVCOEK"
                db.session.add(c)
            db.session.flush()

        college = colleges[0]

        # Update Geofence for Kolhapur campus
        geofence = GeofenceConfig.query.filter_by(college_id=college.id).first()
        if not geofence:
            geofence = GeofenceConfig(
                college_id=college.id,
                latitude=16.6631,
                longitude=74.2642,
                radius_meters=500.0,
                max_accuracy_meters=80.0
            )
            db.session.add(geofence)
        else:
            geofence.latitude = 16.6631
            geofence.longitude = 74.2642
            geofence.radius_meters = 500.0
            geofence.max_accuracy_meters = 80.0
            db.session.add(geofence)

        # Department
        dept = Department.query.filter_by(college_id=college.id, code="CSE").first()
        if not dept:
            dept = Department.query.filter_by(college_id=college.id).first()
        if not dept:
            dept = Department(
                college_id=college.id,
                name="Computer Science & Engineering",
                code="CSE"
            )
            db.session.add(dept)
            db.session.flush()
        else:
            dept.name = "Computer Science & Engineering"
            dept.code = "CSE"

        # Academic Class
        ac_class = AcademicClass.query.filter_by(college_id=college.id, division="A").first()
        if not ac_class:
            ac_class = AcademicClass.query.filter_by(college_id=college.id).first()
        if not ac_class:
            ac_class = AcademicClass(
                college_id=college.id,
                department_id=dept.id,
                name="T.Y. CSE Div- A (2026-27)",
                semester=5,
                division="A",
                academic_year="2026-2027"
            )
            db.session.add(ac_class)
            db.session.flush()
        else:
            ac_class.name = "T.Y. CSE Div- A (2026-27)"
            ac_class.division = "A"
            ac_class.semester = 5
            ac_class.academic_year = "2026-2027"

        # Ensure Subjects exist
        subj1 = Subject.query.filter_by(college_id=college.id, code="CS501").first()
        if not subj1:
            subj1 = Subject(
                college_id=college.id,
                department_id=dept.id,
                name="Database Management Systems",
                code="CS501",
                semester=5
            )
            db.session.add(subj1)
            db.session.flush()

        # Update Teacher
        teacher_user = User.query.filter_by(email="teacher@gcek.ac.in").first()
        if teacher_user:
            teacher_user.full_name = "Prof. V. A. Upadhye"
            teacher_user.college_id = college.id
            if teacher_user.teacher_profile:
                teacher_user.teacher_profile.full_name = "Prof. V. A. Upadhye"
                teacher_user.teacher_profile.college_id = college.id
                teacher_user.teacher_profile.department_id = dept.id

        # Insert or update all 77 students
        count_added = 0
        count_updated = 0
        for roll_int, roll_str, prn, name, batch in STUDENTS_DATA:
            student = StudentProfile.query.filter_by(prn=prn).first()
            if not student:
                # Also check by roll_no
                student = StudentProfile.query.filter_by(college_id=college.id, roll_no=roll_str).first()

            email = f"{prn.lower()}@bvcoek.edu.in"
            if not student:
                user = User(
                    college_id=college.id,
                    email=email,
                    full_name=name,
                    role="STUDENT"
                )
                user.set_password(f"Pass@{prn}")
                db.session.add(user)
                db.session.flush()

                student = StudentProfile(
                    user_id=user.id,
                    college_id=college.id,
                    class_id=ac_class.id,
                    prn=prn,
                    roll_no=roll_str
                )
                db.session.add(student)
                count_added += 1
            else:
                student.prn = prn
                student.roll_no = roll_str
                student.class_id = ac_class.id
                student.college_id = college.id
                if student.user:
                    student.user.full_name = name
                    student.user.college_id = college.id
                count_updated += 1

        db.session.commit()
        print(f"[SUCCESS] Seeded 77 students! Added: {count_added}, Updated: {count_updated}")
        print(f"College: {college.name} ({college.code})")
        print(f"Class: {ac_class.name} (Div {ac_class.division})")
        total = StudentProfile.query.filter_by(class_id=ac_class.id).count()
        print(f"Total students in class: {total}")

if __name__ == '__main__':
    run()
