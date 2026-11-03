# DropClip Engineering Playbook & Contributing Guide

คู่มือแนวทางการทำงานร่วมกันสำหรับทีมพัฒนาโครงการ DropClip ทั้ง 5 คน อ้างอิงตาม `docs/00-PROJECT-PROPOSAL-AND-PLAYBOOK.md`

---

## 1. กฎ 6 ข้อที่ห้ามละเมิด (Non-Negotiable Rules)

1. **Pull Request ห้ามเกิน 400 บรรทัด** (ไม่นับ generated code) — หากเกินแสดงว่า Task ใหญ่เกินไป ต้องซอย Task ย่อยทันที
2. **ห้าม Merge โค้ดที่ไม่มี Test** — ทุก PR ต้องมี Unit Test ครอบคลุม Happy path และ Edge cases อย่างน้อย 3 รูปแบบ
3. **Spike Task มี Timebox ไม่เกิน 4 ชั่วโมง** — หากติดปัญหาเกิน 4 ชั่วโมง ต้องหยุดและขอความช่วยเหลือจาก Lead/เพื่อนร่วมทีมทันที
4. **ห้าม Implement Cryptographic Primitives เอง** — ทุกอย่างต้องใช้ TLS 1.3 และ Secure Keystore มาตรฐานของระบบปฏิบัติการ
5. **ห้ามโหลดไฟล์ทั้งก้อนขึ้นหน่วยความจำ (RAM)** — หากพบคำสั่ง `readAsBytes()` สำหรับงานประมวลผลไฟล์ ให้ Reject PR ทันที (บังคับใช้ Streaming 1 MiB chunk)
6. **ใช้ Conventional Commits เสมอ** — เพื่อรองรับ Automated Changelog และ Traceability

---

## 2. ลำดับขั้นตอนการพัฒนา (Workflow)

กระบวนการพัฒนาแบ่งออกเป็น 2 ส่วนที่แยกจากกันอย่างชัดเจน:
1. **การพัฒนาฟีเจอร์ / โค้ด (ใน Branch ของงาน)**
2. **การบันทึก Worklogs และอัปเดตความคืบหน้างาน (ใน branch `docs/task-progress-tracker` เท่านั้น)**

---

### 2.1 การพัฒนาฟีเจอร์ / โค้ด (Feature / Spike / Bugfix Branch)

> ⚠️ **กฎเหล็กเรื่อง Worklogs & Task Progress:**
>
> **ห้าม commit ไฟล์ใน `docs/worklogs/*` หรือ `docs/TASK-PROGRESS-AND-UPDATES.md` (รวมถึง `UPDATES.md`) เข้า Feature/Spike/Bugfix branch โดยเด็ดขาด!**
>
> เหตุผล:
> 1. ป้องกัน Merge Conflict ระหว่างหลายๆ Feature branch ที่แตกแยกย้ายกันทำ
> 2. รักษาขนาด PR Diff ไม่ให้เกิน 400 บรรทัด (Non-Negotiable Rule #1)
> 3. รวมศูนย์ประวัติการทำงาน (Single Source of Truth) บน branch ติดตามความคืบหน้าส่วนกลาง

ขั้นตอนการทำโค้ด:
```
1. รับ Ticket จาก docs/02-TICKETS.md
2. แตก Branch ออกจาก main:
   - Feature:  git checkout -b feat/<TICKET_ID>-<slug>
   - Spike:    git checkout -b spike/<SPIKE_ID>-<slug>
   - Bug fix:  git checkout -b fix/<TICKET_ID>-<slug>
3. พัฒนาโค้ดและเขียน Test (Happy path + 3 edge cases, Coverage >= 75%)
   *(หมายเหตุ: ห้ามสร้างหรือ commit worklogs ลงใน branch นี้)*
4. ตรวจสอบคุณภาพโค้ดก่อน Commit:
   - melos run format
   - melos run analyze
   - melos run test
5. Commit เฉพาะไฟล์โค้ดและชุดทดสอบของงานนั้นๆ (Diff <= 400 บรรทัด)
6. เปิด Pull Request พร้อมกรอก Checklist ตาม PR Template
7. ได้รับ Code Review Approved อย่างน้อย 1 คน (งานด้าน Security ต้องผ่าน LEAD)
8. Squash and Merge เข้าสู่ main
```

---

### 2.2 การบันทึก Worklogs & Task Progress (บน branch `docs/task-progress-tracker` เท่านั้น)

ทุกคนในทีม (Developer ทั้ง 5 คน และ AI Coding Assistants ทุกตัว) **ต้องบันทึก Worklogs และอัปเดตกระดานสถานะงานใน branch `docs/task-progress-tracker` เท่านั้น**:

```bash
# 1. สลับมาที่ branch กลาง docs/task-progress-tracker และ pull ข้อมูลล่าสุด
git checkout docs/task-progress-tracker
git pull origin docs/task-progress-tracker

# 2. บันทึก Work Log ประจำ Ticket:
#    - สร้างไฟล์ docs/worklogs/<TICKET_ID>-<slug>.md (อิงตาม docs/worklogs/TEMPLATE.md)
#    - หรือบันทึกต่อท้าย docs/worklogs/WORK_LOG.md
#    - สรุปสิ่งที่มีการเปลี่ยนแปลง, การตัดสินใจทางเทคนิค และผลการรัน Test

# 3. อัปเดตกระดานสถานะใน docs/TASK-PROGRESS-AND-UPDATES.md (หรือ UPDATES.md):
#    - ติ๊กเครื่องหมาย [x] ที่ Ticket ของคุณใน "1. Ticket Status Board"
#    - เพิ่มแถวในตาราง "2. Branch & Completed Tasks Registry":
#      - Ticket ID, Branch Name, Assignee (LEAD, DESK, MOB, NET, QA)
#      - Status (READY FOR PR / MERGED), Commit Hash ล่าสุด, วันที่
#      - สรุปผลงาน และผลการรัน Test Verification (Format, Analyze, Test Pass)

# 4. Commit และ Push ไปยัง docs/task-progress-tracker โดยตรง
git add docs/worklogs/ docs/TASK-PROGRESS-AND-UPDATES.md
git commit -m "docs(updates): update task progress and worklog for <TICKET_ID>"
git push origin docs/task-progress-tracker
```

> **คำแนะนำสำหรับ AI Coding Assistants (Cursor, Copilot, Antigravity, etc.):**
> ให้อ่านและปฏิบัติตาม [`AGENTS.md`](AGENTS.md) และ [`.cursorrules`](.cursorrules) อย่างเคร่งครัด
> **ห้าม** แก้ไขหรือ commit ไฟล์ worklogs / progress ลงใน feature branch ที่กำลังพัฒนาโค้ด ให้สลับไปทำบน `docs/task-progress-tracker` เท่านั้น

---

## 3. รูปแบบข้อความ Commit (Commit Message Convention)

```
<type>(<scope>): <short description> (<TICKET_ID>)

ตัวอย่าง:
feat(discovery): implement mdns advertiser and browser (T1.1)
fix(clipboard): resolve suppression window race condition (T1.9)
test(protocol): add sas conformance test vectors (T0.2)
```

ประเภทของ Type:
- `feat`: ฟีเจอร์ใหม่
- `fix`: แก้ไขบั๊ก
- `refactor`: ปรับโครงสร้างโค้ดโดยไม่เปลี่ยนพฤติกรรม
- `test`: เพิ่มหรือแก้ไขชุดทดสอบ
- `docs`: แก้ไขเอกสาร
- `chore`: งานทั่วไปหรือการอัปเดต dependencies

