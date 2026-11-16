# Work Log — DOCS-M1-M2: Research CSVs and Survey Link

| รายการ | รายละเอียด |
|---|---|
| Scope ID | `DOCS-M1-M2` (งานเอกสาร M1/M2 ใน SRS §2.2 ไม่ใช่ engineering ticket) |
| Branch | `docs/M1-M2-research-artifacts` |
| Assignee | นายเกื้ออนันต์ พวงนิลน้อย (เกื้อ), `MOB` |
| AI Assistant | Codex |
| Date | 2026-11-17 (Asia/Bangkok) |
| Status | `READY FOR REVIEW` |
| Commit | `8d07230` |
| PR | [#124](https://github.com/nCotista/DropClip/pull/124) |

## Objective and Scope

- ส่ง `M1_summary.csv` และ `M2_question_answers.csv` ตามไฟล์ที่ผู้ใช้เลือก พร้อมลิงก์ Google Form ให้ LEAD รีวิว
- เพิ่ม README ระบุข้อมูลจำลองและข้อจำกัด เพื่อแยกจากคำตอบจริงในฟอร์ม
- ขอรีวิวจาก `nCotista` (Thanakrit Boonyaworakul, LEAD)

## Changes and Decisions

- สร้าง checkout แยกจาก `origin/main` (`dbbb1cd`) เพื่อไม่รวม commit ของ branch Android เดิม
- PR มีเฉพาะ CSV สองไฟล์และ README ใน `deliverables/2026-11-16/simulated-research/` รวม `+124/-0`
- เก็บชื่อไฟล์และข้อมูลตามต้นทาง ไม่แก้เนื้อหา CSV
- M1 มี 64 แถวสรุปจากข้อมูลจำลอง 20 ราย; M2 มี 30 รายการ จาก 6 ราย กลุ่มละ 2 ราย
- ระบุ INTSIM07 / M2-Q05 ที่ยังไม่มีคำตอบ โดยไม่ตีความเป็นคำตอบปฏิเสธ
- ไม่เปลี่ยน SRS หรือสถานะการเก็บข้อมูลจริง ไม่แตะ source code หรือ protocol
- บันทึกนี้และ progress registry อยู่บน `docs/task-progress-tracker` เท่านั้น

## Validation

- CSV: UTF-8 BOM, จำนวนคอลัมน์สม่ำเสมอ, สำเนาใน working tree ตรงต้นทางทุกไบต์
- M1: ตรวจ 64 คู่กลุ่ม/คำถามไม่ซ้ำ, ฐาน ALL/P1/P2/P3 = 20/7/7/6, ผลรวมการกระจายคะแนน, missing counts, mean, median, sample SD และร้อยละคะแนน 4–5; Q07 ฐาน ALL = 18
- M2: 6 รหัสไม่ซ้ำ กลุ่มละ 2 ราย คนละ 5 คำถาม มีรายการยังไม่มีคำตอบ 1 รายการ
- Google Form <https://forms.gle/2JjwzDrbL9Thkqps6>: HTTP 200, ชื่อแบบสอบถาม DropClip ตรงกัน; ไม่ส่งคำตอบทดสอบ
- `git diff --check` ผ่าน; มีเฉพาะ 3 ไฟล์ที่อนุญาตใน PR
- ไม่รัน Melos format/analyze/tests หรืออ้าง code coverage เนื่องจากเปลี่ยนเอกสาร/CSV เท่านั้น
- ตรวจ GitHub ยืนยัน PR เป็น `OPEN`, base `main`, reviewer request `nCotista`; ตอนบันทึก CI ยัง `IN_PROGRESS`

## Reviewer Notes

- LEAD ตรวจความเหมาะสมของแบบคำถามและข้อจำกัดข้อมูลจำลองก่อนอนุมัติ
- คำตอบจริงจาก Google Form ต้องเก็บแยกจากชุดจำลอง
- ยังไม่ merge PR และไม่อ้างว่าการสำรวจ/สัมภาษณ์จริงเสร็จสิ้นแล้ว
