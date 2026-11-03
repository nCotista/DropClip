# DropClip — Central Task Progress & Updates

> **Single Source of Truth:**  
> กระดานติดตามสถานะงาน และสมุดลงทะเบียนการจบงานประจำ Branch ส่วนกลางของโครงการ DropClip อยู่ที่:  
> 👉 [**`docs/TASK-PROGRESS-AND-UPDATES.md`**](docs/TASK-PROGRESS-AND-UPDATES.md)

---

## 🚀 กฎเหล็ก: การอัปเดตสถานะงานและ Worklogs (บน branch `docs/task-progress-tracker` เท่านั้น)

> ⚠️ **คำเตือน:** ห้าม commit การอัปเดตไฟล์นี้ หรือไฟล์ใน `docs/worklogs/` เข้าสู่ feature/spike/fix branch โดยเด็ดขาด ให้สลับมาทำบน branch `docs/task-progress-tracker` เท่านั้น!

1. สลับมาที่ branch `docs/task-progress-tracker` (`git checkout docs/task-progress-tracker && git pull origin docs/task-progress-tracker`)
2. เปิดไฟล์ [`docs/TASK-PROGRESS-AND-UPDATES.md`](docs/TASK-PROGRESS-AND-UPDATES.md)
3. ติ๊กสถานะ Ticket ของคุณเป็น `[x]` ใน **Ticket Status Board**
4. เพิ่มแถวบันทึกผลงานในตาราง **Branch & Completed Tasks Registry**:
   - ระบุ Ticket ID, Branch Name, Assignee (Role Code)
   - Commit Hash, วันที่ และสรุปผลการทดสอบ (Test Evidence)
5. บันทึก Work Log ของคุณใน [`docs/worklogs/`](docs/worklogs/)
6. Commit และ Push ไปยัง `docs/task-progress-tracker`:
   ```bash
   git add docs/TASK-PROGRESS-AND-UPDATES.md docs/worklogs/
   git commit -m "docs(updates): update task progress and worklog for <TICKET_ID>"
   git push origin docs/task-progress-tracker
   ```

