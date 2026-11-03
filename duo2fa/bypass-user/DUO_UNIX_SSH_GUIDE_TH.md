# KB: สร้าง Group สำหรับ Bypass User บางส่วนใน Duo Unix

## เป้าหมายและรูปแบบการตั้งค่า

ตัวอย่างนี้ตั้ง Duo MFA สำหรับ SSH โดยยกเว้นเฉพาะบัญชีที่เป็นสมาชิกกลุ่ม `duo-bypass` ผู้ใช้อื่น เช่น `MFA_USER` จะต้องผ่าน Duo ส่วน `root` เป็นตัวอย่างบัญชีที่ถูกเพิ่มเข้า bypass group ตามความต้องการของระบบนี้

แนวทางนี้ใช้ `groups = *,!duo-bypass`: `*` ใช้กับผู้ใช้ทุกกลุ่ม และ `!duo-bypass` ตัดสมาชิกของกลุ่ม bypass ออก Duo ระบุว่าเครื่องหมาย `!` เป็นตัวกรอง ไม่ใช่กฎเดี่ยว จึงต้องมี positive wildcard `*` รวมอยู่ด้วย

> สมาชิก `duo-bypass` จะล็อกอินโดยไม่ผ่าน Duo MFA จริง จำกัดสมาชิกในกลุ่มนี้ให้น้อยที่สุด และตรวจสอบบัญชีที่ได้รับยกเว้นเป็นระยะ

มี 2 รูปแบบให้เลือกตอนตั้ง SSH:

- **รหัสผ่าน Linux ผ่าน PAM แล้ว Duo**: ใช้ `keyboard-interactive` สำหรับ `MFA_USER` ตามตัวอย่างการทดสอบที่ใช้งานได้
- **SSH key แล้ว Duo**: ใช้ public key เป็นขั้นแรก และ `keyboard-interactive` เป็นขั้นที่สอง ตามแนวทาง Duo

อย่าตั้งสองรูปแบบปนกันโดยไม่ตั้งใจ ดูหัวข้อ 7 เพื่อเลือกวิธีให้ตรงกับการใช้งานของลูกค้า

## ดาวน์โหลดคู่มือและสคริปต์

Clone repository แล้วเข้าโฟลเดอร์ของวิธี bypass user:

```bash
git clone https://github.com/saranse/duo2fa-bypass-user-.git && cd duo2fa-bypass-user-/duo2fa/bypass-user && chmod 700 setup_duo_bypass.sh && sudo ./setup_duo_bypass.sh
```

## ต้องติดตั้ง Duo ไว้ก่อนหรือไม่

Duo Unix ติดตั้งที่ระดับเครื่อง Linux ไม่ได้ติดตั้งแยกตาม user การ bypass จะมีผลเมื่อเครื่องตั้ง PAM Duo สำหรับ SSH แล้ว **เมนูข้อ 1 เวอร์ชันปัจจุบันใช้ Duo package และ Key จาก config เดิมเท่านั้น** โดยตรวจว่ามี package, `/etc/duo/pam_duo.conf` ที่มี `ikey`/`skey`/`host`, PAM module และ SSH service ทำงานอยู่ก่อน ไม่ติดตั้ง package และไม่ถามหรือเขียนทับ Key หากตรวจไม่พบ config เดิม สคริปต์จะหยุดและแจ้งให้ตั้งค่า Duo ก่อน

ข้อ 1 จะคง Duo Key และค่า `failmode` ใน config เดิมไว้ แล้วปรับเฉพาะกฎ `groups = *,!duo-bypass` พร้อมตั้ง PAM/SSH ตามสคริปต์ และสำรองไฟล์ก่อนแก้ บัญชี Linux ที่ระบุเป็น `--duo-user` ต้องมีอยู่และถูก provision/enroll ใน Duo ส่วนบัญชีใน `--bypass-users` ต้องมีบัญชี Linux และจะไม่ถูกถาม Duo สำหรับ SSH ตาม policy นี้

## ติดตั้งอัตโนมัติด้วยสคริปต์

ใน repository มีสคริปต์ `setup_duo_bypass.sh` สำหรับ Ubuntu amd64 และ AlmaLinux โดยเมนูข้อ 1 จะตรวจ Duo Unix และ config ที่มีอยู่ ไม่ติดตั้ง package หรือถาม Key ใหม่ สร้างกลุ่ม `duo-bypass` หากยังไม่มี เพิ่มบัญชีที่ระบุ ตั้ง PAM/SSH และตรวจ config ก่อน reload SSH

รันโดยไม่ใส่ option เพื่อเปิดเมนู `DUO 2FA`:

```bash
sudo ./setup_duo_bypass.sh
```

เมนูข้อ 1 ใช้กับเครื่องที่มี Duo ทำงานอยู่แล้ว: ระบุ Linux user ที่ต้องผ่าน Duo และ user ที่ต้อง bypass จากนั้นสคริปต์คง Key เดิมไว้ ปรับ group policy/PAM/SSH และสร้าง backup ก่อนแก้ ถ้าไม่มี Duo package หรือ config เดิม สคริปต์จะหยุดโดยไม่ติดตั้งและไม่ขอ Key

เมนูข้อ 2 ใช้เพิ่มบัญชี bypass หลังมีการตั้งค่าแล้ว โดยเปลี่ยนสมาชิกกลุ่มเท่านั้น เมนูข้อ 3 ใช้ rollback เลือก backup ใน `/root/duo-setup-backup-*` เพื่อคืนไฟล์ PAM/SSH/Duo config และสมาชิกกลุ่ม bypass ที่บันทึกไว้ สคริปต์จะถามยืนยันก่อน rollback ทุกครั้ง

ตัวอย่าง: บังคับ Duo ให้ `MFA_USER` และยกเว้น `root` กับ `svcbackup`:

```bash
chmod 700 setup_duo_bypass.sh
sudo ./setup_duo_bypass.sh --duo-user MFA_USER --bypass-users root,svcbackup
```

ความหมายของค่าที่ใส่:

- `MFA_USER` คือ **ชื่อ user Linux จริง** ที่ต้องการให้ SSH login ผ่าน Duo เช่น `saran` ให้แทนคำว่า `MFA_USER` ด้วยชื่อนั้น ห้ามพิมพ์ `MFA_USER` ตรง ๆ เว้นแต่ชื่อบัญชี Linux ของคุณเป็นชื่อนี้จริง บัญชีนี้ต้องมีอยู่บนเครื่องและถูก provision/enroll ใน Duo
- `root,svcbackup` คือ **รายชื่อ user Linux ที่ยกเว้น Duo** ในตัวอย่าง `root` และ `svcbackup` จะไม่ถูกถาม Duo ผ่าน SSH ให้ใส่เฉพาะบัญชีที่มีอยู่จริง คั่นหลายบัญชีด้วย comma และไม่เว้นวรรค เช่น `root,serviceuser` เอา `root` ออกจากรายการถ้าไม่ต้องการยกเว้น root
- สคริปต์สร้างกลุ่ม `duo-bypass` และเพิ่มบัญชีใน `--bypass-users` ให้เอง ไม่ต้องสร้างกลุ่มก่อน แต่จะไม่สร้างบัญชี Linux ให้

สคริปต์ตั้งค่า `MFA_USER` ให้ใช้รหัสผ่าน Linux ผ่าน `keyboard-interactive` แล้วทำ Duo MFA โดยปิด SSH public-key login สำหรับบัญชีนี้ จึงให้ทดสอบตามคำสั่งที่สคริปต์แสดง และอย่าปิด session root เดิมจนกว่าจะยืนยันว่า login ใหม่สำเร็จ สคริปต์สำรองไฟล์ PAM และ SSH ไว้ที่ `/root/duo-setup-backup-*` และพยายามคืนไฟล์เหล่านั้นหากขั้นตอนตั้งค่าล้มเหลว

การตั้งค่า AlmaLinux ใช้ Duo RPM repository สำหรับ RHEL ซึ่งเป็นการอาศัยความเข้ากันได้ของ AlmaLinux กับ RHEL; ทดสอบในระบบ staging ก่อนใช้งานจริง สคริปต์ไม่ได้ลบ package หรือ repository ที่ติดตั้งไว้หากเกิด rollback

## สถานะจากเครื่องตัวอย่าง

- Ubuntu, amd64
- Duo Unix 2.3.0 ติดตั้งแล้ว
- PAM module อยู่ที่ `/lib64/security/pam_duo.so`
- ก่อนเปลี่ยนมาใช้ bypass group ตัวอย่างเดิมมี `duo-required` และ `groups = duo-required`
- รูปแบบใน KB นี้เปลี่ยนเป็น `duo-bypass` และ `groups = *,!duo-bypass`
- ตัวอย่างนี้ใช้ `failmode = safe` ตามความต้องการให้ล็อกอินต่อได้เมื่อ Duo ติดต่อไม่ได้
- ใน log ล่าสุด `sshd -T` แสดง `UsePAM yes`, `PasswordAuthentication yes`, `KbdInteractiveAuthentication yes`, `UseDNS yes`

`failmode = safe` เป็นแบบ fail-open เมื่อ Duo มีปัญหาด้านการเชื่อมต่อหรือ configuration; หากต้องการปฏิเสธ login ในกรณีดังกล่าวให้ใช้ `secure` แทน ตรวจให้ `UseDNS no` มีผลจริงตามหัวข้อด้านล่าง

## 1. เพิ่ม repository และติดตั้งแพ็กเกจ

เลือกคำสั่งตาม Linux distribution เครื่อง Duo GPG key มีอยู่แล้ว `--yes` จะอนุญาตให้เขียนทับไฟล์ key เดิมด้วย key ทางการ

### Ubuntu

คำสั่งนี้อ่าน codename จาก `/etc/os-release` เพื่อใช้ repository ให้ตรงกับ Ubuntu เครื่องนั้น:

```bash
curl -fsSL https://duo.com/DUO-GPG-PUBLIC-KEY.asc \
  | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/duo.gpg

. /etc/os-release
printf 'deb [arch=amd64] https://pkg.duosecurity.com/Ubuntu %s main\n' "$VERSION_CODENAME" \
  | sudo tee /etc/apt/sources.list.d/duosecurity.list

sudo apt-get update
sudo apt-get install -y duo-unix
```

### AlmaLinux

คำสั่งนี้ใช้ Duo RPM repository สำหรับ Red Hat Enterprise Linux ซึ่งเป็นตระกูล RPM ที่ AlmaLinux เข้ากันได้:

```bash
sudo rpm --import https://duo.com/DUO-GPG-PUBLIC-KEY.asc

sudo tee /etc/yum.repos.d/duosecurity.repo >/dev/null <<'EOF'
[duosecurity]
name=Duo Security Repository
baseurl=https://pkg.duosecurity.com/RedHat/$releasever/$basearch
enabled=1
gpgcheck=1
EOF

sudo dnf makecache --refresh
sudo dnf info duo_unix
sudo dnf install -y duo_unix
```

Duo ระบุ repository สำหรับ Red Hat Enterprise Linux แต่ไม่ได้ระบุ AlmaLinux แยกเป็นแพลตฟอร์มที่ทดสอบไว้ จึงเป็นการใช้ RHEL-compatible repository ให้ตรวจว่า package มีให้ติดตั้งด้วย `dnf info duo_unix` และทดสอบในสภาพแวดล้อมของตนก่อนใช้งานจริง ([Duo Unix](https://duo.com/docs/duounix))

### ตรวจ package และตำแหน่ง PAM module

บน Ubuntu:

```bash
dpkg-query -W -f='${Status} ${Version}\n' duo-unix
dpkg -L duo-unix | grep '/pam_duo.so$'
```

บน AlmaLinux:

```bash
rpm -q duo_unix
rpm -ql duo_unix | grep '/pam_duo.so$'
```

ผลที่เครื่องตัวอย่าง:

```text
install ok installed 2.3.0-0
/lib64/security/pam_duo.so
```

ถ้า `dpkg` แจ้งว่าเป็นเวอร์ชันล่าสุดแล้ว ไม่ต้องติดตั้งซ้ำ

## 2. สร้างกลุ่มสำหรับ Bypass User บางส่วน

สร้างกลุ่มสำหรับบัญชีที่ยกเว้น Duo โดยตรวจว่ากลุ่มยังไม่มีอยู่ก่อน:

```bash
getent group duo-bypass >/dev/null || sudo groupadd duo-bypass
sudo usermod -aG duo-bypass root
sudo usermod -aG duo-bypass USER_TO_BYPASS
getent group duo-bypass
id root
id USER_TO_BYPASS
id MFA_USER
```

แทน `USER_TO_BYPASS` ด้วยบัญชี Linux ที่ต้องการยกเว้น หากยกเว้นเฉพาะ `root` ให้ข้ามคำสั่ง `usermod` สำหรับ `USER_TO_BYPASS`. ตรวจว่า `root` และบัญชีที่ระบุอยู่ใน `duo-bypass` ส่วน `MFA_USER` ไม่อยู่ในกลุ่มนี้

หากกำลังเปลี่ยนจาก allowlist `duo-required` ให้ลบการตั้งค่า `groups = duo-required` ในขั้นถัดไป แล้วแทนด้วย `groups = *,!duo-bypass`. อย่าลบกลุ่มเดิมจนกว่าจะตรวจสมาชิกและแน่ใจว่าไม่มีบริการอื่นใช้กลุ่มนั้น

## 3. ตั้งค่า Duo application

ถ้าไฟล์ยังไม่มี ให้สร้างไฟล์ด้วย permission ที่ปลอดภัยก่อนเปิดแก้ไข:

```bash
sudo install -o root -g root -m 600 /dev/null /etc/duo/pam_duo.conf
sudo nano /etc/duo/pam_duo.conf
```

> คำสั่ง `install ... /etc/duo/pam_duo.conf` จะเขียนทับไฟล์เดิม หากมี credentials ที่ต้องเก็บอยู่แล้ว ให้ข้ามคำสั่ง `install` และเปิดไฟล์ด้วย `sudo nano` แทน

ใส่ค่า Duo Unix Application จาก Duo Admin Panel โดยแทนค่าตัวอย่าง ห้ามนำ `skey` ไปใส่ในคู่มือหรือส่งในแชต:

```ini
[duo]
; Duo integration key
ikey = YOUR_INTEGRATION_KEY
; Duo secret key
skey = YOUR_SECRET_KEY
; Duo API host
host = api-XXXXXXXX.duosecurity.com
; safe allows access when Duo service or configuration errors prevent Duo authentication.
; secure denies access in those cases.
; With safe, login can continue without Duo when Duo is unavailable.
failmode = safe
; Send command for Duo Push authentication
;pushinfo = yes
groups = *,!duo-bypass
```

ค่า `failmode` ที่ Duo รองรับคือ `safe` และ `secure`; `failmode = false` ไม่ใช่ค่าที่ถูกต้อง หากตั้ง `safe` แล้ว Duo service ติดต่อไม่ได้หรือ configuration มี error ระบบอาจอนุญาตให้ผ่านโดยไม่มี Duo MFA ซึ่งเป็น fail-open ตามที่ต้องการ แต่หมายความว่า network/configuration error อาจลดการป้องกัน MFA ด้วย หากต้องการปฏิเสธ login เมื่อ Duo ใช้งานไม่ได้ ให้เปลี่ยนเป็น `failmode = secure` และทดสอบโดยเปิด session ผู้ดูแลเดิมค้างไว้

ตั้ง owner และ permission หลังแก้ไฟล์:

```bash
sudo chown root:root /etc/duo/pam_duo.conf
sudo chmod 600 /etc/duo/pam_duo.conf
sudo stat -c '%U:%G %a %n' /etc/duo/pam_duo.conf
```

ผลที่ต้องการ:

```text
root:root 600 /etc/duo/pam_duo.conf
```

`644` ไม่ได้ปิด Duo โดยตรง เพราะ PAM ยังอ่านไฟล์ได้ แต่เปิดให้ผู้ใช้เครื่องอื่นอ่าน `skey` ได้ จึงต้องใช้ `600`

## 4. สำรองและเพิ่ม PAM module

คง session `root` เดิมไว้ตลอดการตั้งค่า สำรองไฟล์ก่อนแก้:

```bash
sudo cp -a /etc/pam.d/sshd /etc/pam.d/sshd.before-duo
```

ตรวจ path ของ module ตาม distribution:

```bash
dpkg -L duo-unix | grep '/pam_duo.so$'
```

บน AlmaLinux:

```bash
rpm -ql duo_unix | grep '/pam_duo.so$'
```

เปิด PAM config:

```bash
sudo nano /etc/pam.d/sshd
```

### Ubuntu

เพิ่มบรรทัดนี้ถัดจาก `@include common-auth`:

```text
auth required /lib64/security/pam_duo.so
```

ใช้ path ที่ `dpkg -L` แสดงบน Ubuntu จริง หากแสดง path อื่น ให้ใส่ path นั้นแทน ตรวจไม่ให้มีบรรทัด `pam_duo.so` ซ้ำ:

```bash
sudo grep -nE 'common-auth|pam_duo' /etc/pam.d/sshd
```

ตัวอย่างตำแหน่งที่ต้องการ:

```text
@include common-auth
auth required /lib64/security/pam_duo.so
```

### AlmaLinux

ตรวจ path ด้วย `rpm -ql duo_unix` แล้วเลือก PAM snippet ให้ตรงกับวิธี SSH ที่ใช้ PAM ใน AlmaLinux ใช้โครงสร้างแบบ RHEL; ตรวจ `/etc/pam.d/sshd` ของเครื่องก่อนแก้

สำหรับ **รหัสผ่าน Linux ผ่าน PAM แล้ว Duo** ให้คง `auth substack password-auth` ไว้ และเพิ่ม module ถัดจากบรรทัดนั้น:

```bash
sudo nano /etc/pam.d/sshd
```

ตัวอย่าง password + Duo:

```text
auth substack password-auth
auth required /lib64/security/pam_duo.so
```

สำหรับ **SSH public key แล้ว Duo** ให้ใช้โครงสร้าง PAM แบบ RHEL-compatible โดยแทน path ด้วยผลจาก `rpm -ql`:

```text
auth required pam_sepermit.so
#auth substack password-auth
auth required /lib64/security/pam_duo.so
auth include postlogin
```

ตรวจไฟล์เดิมและวางบรรทัดให้เข้ากับ PAM stack ของเครื่อง อย่าแทนทั้งไฟล์โดยไม่ตรวจ config เดิม และอย่ารัน `authconfig` หลังแก้ PAM เพราะอาจเขียนทับการเปลี่ยนแปลง

## 5. เปิด SSH PAM และ keyboard-interactive

ก่อนแก้ ให้ดูค่าที่กำหนดไว้ทั้งในไฟล์หลักและ drop-in:

```bash
sudo grep -RniE '^[[:space:]]*(UsePAM|KbdInteractiveAuthentication|ChallengeResponseAuthentication|PasswordAuthentication|UseDNS|AuthenticationMethods)[[:space:]]' \
  /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null
```

แก้ `/etc/ssh/sshd_config`:

```bash
sudo nano /etc/ssh/sshd_config
```

ให้ค่าที่มีผลเป็น:

```text
UsePAM yes
KbdInteractiveAuthentication yes
UseDNS no
```

`KbdInteractiveAuthentication yes` จำเป็นสำหรับ Duo prompt หากยังเป็น `no` จะเกิด `conversation failed` ได้ ตรวจค่า effective หลังบันทึก:

```bash
sudo sshd -t
sudo sshd -T | grep -Ei '^(usepam|kbdinteractiveauthentication|passwordauthentication|usedns|authenticationmethods) '
```

ค่าพื้นฐานที่ต้องเห็นคือ:

```text
usepam yes
kbdinteractiveauthentication yes
usedns no
```

`UseDNS yes` ไม่ใช่สาเหตุหลักที่ข้าม Duo แต่ Duo แนะนำ `UseDNS no` เพื่อส่ง IP ของ client ได้ตรงในการประเมิน network policy

บน AlmaLinux ให้ตรวจ SSH drop-in ด้วย โดยเฉพาะ `/etc/ssh/sshd_config.d/50-redhat.conf` หากมี `ChallengeResponseAuthentication no` ให้ comment บรรทัดนั้นออก แล้วตรวจว่า `sshd -T` แสดง `kbdinteractiveauthentication yes` จริง:

```bash
sudo grep -RniE 'ChallengeResponseAuthentication|KbdInteractiveAuthentication' \
  /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null
sudo sshd -T | grep -Ei '^(usepam|kbdinteractiveauthentication|usedns) '
```

## 6. บังคับให้ `MFA_USER` ผ่าน Duo ทุกครั้ง

การเปิด PAM และ keyboard-interactive อย่างเดียว **ไม่ได้บังคับว่าทุก authentication method ต้องเรียก Duo** หาก SSH ยังยอมรับ `publickey` หรือ `password` เป็นวิธีเดี่ยว การล็อกอินอาจไม่เข้าสู่ keyboard-interactive PAM flow

ตรวจ effective setting สำหรับ `MFA_USER`:

```bash
sudo sshd -T -C user=MFA_USER,host=SSH_SERVER,addr=CLIENT_IP \
  | grep -Ei '^(authenticationmethods|passwordauthentication|kbdinteractiveauthentication|usepam) '
```

เปลี่ยน `addr` เป็น IP เครื่อง client จริง หาก `authenticationmethods any` ให้เลือกวิธีในหัวข้อ 7 แล้วกำหนด `AuthenticationMethods` สำหรับ `MFA_USER`

## 7. เลือกวิธี SSH ที่ต้องการ

### วิธี A: รหัสผ่าน Linux ผ่าน PAM แล้ว Duo

ใช้เมื่อ `MFA_USER` ไม่มี SSH key ที่ต้องการบังคับใช้ และต้องการ flow แบบ password แล้ว Duo Push:

```text
Match User MFA_USER
    AuthenticationMethods keyboard-interactive
    PasswordAuthentication no
```

วางไว้ท้าย `/etc/ssh/sshd_config` หลัง global directives ทั้งหมด ตรวจว่า `KbdInteractiveAuthentication yes` และ `UsePAM yes` อยู่ก่อนบรรทัด `Match` วิธีนี้ให้ SSH ใช้ PAM keyboard-interactive ซึ่งจะถามรหัสผ่าน Linux แล้วตามด้วย Duo

### วิธี B: SSH public key แล้ว Duo

ใช้เมื่อ `MFA_USER` มี public key ติดตั้งใน `~MFA_USER/.ssh/authorized_keys` และต้องการให้ key เป็นปัจจัยแรก:

```text
Match User MFA_USER
    AuthenticationMethods publickey,keyboard-interactive
    PasswordAuthentication no
```

Duo ระบุรูปแบบ `publickey,keyboard-interactive` สำหรับ public-key authentication โดยต้องเปิด `UsePAM yes` และ `KbdInteractiveAuthentication yes` ด้วย

หลังเลือกวิธีใดวิธีหนึ่ง:

```bash
sudo sshd -t
sudo sshd -T -C user=MFA_USER,host=SSH_SERVER,addr=CLIENT_IP \
  | grep -Ei '^(authenticationmethods|passwordauthentication|kbdinteractiveauthentication|usepam) '
sudo systemctl reload ssh
```

เก็บ session `root` เดิมไว้จนกว่าจะทดสอบล็อกอินใหม่สำเร็จ

## 8. ทดสอบจาก Mac

### ทดสอบวิธี A: password + Duo

```bash
ssh -o PreferredAuthentications=keyboard-interactive \
  -o PubkeyAuthentication=no MFA_USER@SSH_SERVER
```

คาดว่าจะเห็น prompt รหัสผ่าน Linux แล้วตามด้วย Duo Push/passcode

### ทดสอบวิธี B: public key + Duo

```bash
ssh -vv MFA_USER@SSH_SERVER
```

คาดว่าจะยืนยัน public key แล้วเข้าสู่ keyboard-interactive prompt และ Duo อย่าใช้ `PubkeyAuthentication=no` สำหรับการทดสอบวิธีนี้

## 9. ตรวจ log เมื่อยังไม่ผ่าน

รันบน server หลังการลองล็อกอิน:

```bash
sudo journalctl -u ssh --since '5 minutes ago' --no-pager
```

แนวแปลผล:

- `PAM unable to dlopen(pam_duo.so)` — module path ผิด ตรวจด้วย `dpkg -L duo-unix` และใช้ full path
- `conversation failed` — ตรวจ `KbdInteractiveAuthentication yes` และวิธี authentication ที่กำหนด
- `Failed password` หรือ `pam_unix ... authentication failure` — รหัสผ่าน Linux ไม่ผ่าน
- Duo Push สำเร็จและเข้า shell ได้ — Duo flow ทำงาน

ห้ามส่ง `skey`, รหัสผ่าน หรือ screenshot ที่มองเห็น credentials

ถ้าเข้า shell แล้วเห็น `Could not chdir to home directory /home/MFA_USER`, สร้าง home directory:

```bash
sudo install -d -o MFA_USER -g MFA_USER -m 0750 /home/MFA_USER
```

## 10. ยืนยันการยกเว้น root

```bash
id root
id MFA_USER
getent group duo-bypass
```

`root` และบัญชีที่แสดงเป็นสมาชิก `duo-bypass` จะถูกยกเว้น MFA โดย `groups = *,!duo-bypass`; `MFA_USER` ซึ่งอยู่นอกกลุ่มต้องผ่าน Duo เมื่อ SSH ถูกตั้งให้เรียก keyboard-interactive ตามวิธีที่เลือก

## เพิ่มหรือเปลี่ยนผู้ใช้ภายหลัง

### เพิ่มบัญชี bypass

บัญชี Linux ต้องมีอยู่แล้ว จากนั้นเพิ่มเข้ากลุ่มโดยตรง ไม่ต้องรัน setup script ซ้ำ:

```bash
id USER_TO_BYPASS
sudo usermod -aG duo-bypass USER_TO_BYPASS
id USER_TO_BYPASS
getent group duo-bypass
```

แทน `USER_TO_BYPASS` ด้วยชื่อบัญชีจริง การเป็นสมาชิกกลุ่มนี้ยกเว้น Duo สำหรับ SSH ให้บัญชีนั้น เปิด SSH session ใหม่เพื่อทดสอบ และตรวจให้แน่ใจว่าตั้งใจยกเว้นบัญชีดังกล่าว

### เพิ่มบัญชีที่ต้องผ่าน Duo

บัญชี Linux ใหม่ต้องมีอยู่ก่อน และต้องถูก provision/enroll ใน Duo Admin Panel หากบัญชีอยู่ใน `duo-bypass` ให้นำออก:

```bash
sudo gpasswd -d NEW_MFA_USER duo-bypass
```

เพิ่ม policy ใน `/etc/ssh/sshd_config` เพื่อบังคับให้บัญชีนั้นใช้ PAM keyboard-interactive แล้วตามด้วย Duo (กรณี password + Duo):

```text
Match all
Match User NEW_MFA_USER
    AuthenticationMethods keyboard-interactive
    PasswordAuthentication no
```

แทน `NEW_MFA_USER` ด้วยชื่อบัญชีจริง จากนั้นตรวจ config และ reload:

```bash
sudo sshd -t
sudo sshd -T -C user=NEW_MFA_USER,host=SSH_SERVER,addr=CLIENT_IP \
  | grep -Ei '^(authenticationmethods|passwordauthentication|kbdinteractiveauthentication|usepam) '
sudo systemctl reload ssh
```

เปิด session root เดิมค้างไว้และทดสอบล็อกอินใหม่ก่อนปิด session สำหรับ public key + Duo ให้ใช้ `AuthenticationMethods publickey,keyboard-interactive` แทนสองบรรทัด policy ข้างต้น

สคริปต์นี้ตั้ง policy `Match User` ให้บัญชีเดียวที่ระบุใน `--duo-user` ตอนติดตั้งครั้งแรก การเพิ่ม MFA user ในภายหลังให้เพิ่ม SSH `Match` policy ตามตัวอย่าง ไม่ควรรันสคริปต์ซ้ำโดยเปลี่ยน `--duo-user` เพราะสคริปต์ไม่ได้เพิ่ม user ใหม่เข้า Match block เดิมโดยอัตโนมัติ

## Rollback

จาก session ผู้ดูแลเดิม คืน PAM และค่าที่เปลี่ยนใน SSH config จาก backup/แก้กลับ แล้วตรวจและ reload:

```bash
sudo cp -a /etc/pam.d/sshd.before-duo /etc/pam.d/sshd
sudo sshd -t
sudo systemctl reload ssh
```

ถ้าต้องการปิด Duo ทั้งหมด ให้เอาบรรทัด `auth required /lib64/security/pam_duo.so` ออกจาก `/etc/pam.d/sshd` และเอา `Match User MFA_USER` ที่บังคับ `AuthenticationMethods` ออกด้วย จากนั้นตรวจ `sshd -t` ก่อน reload

## เอกสารอ้างอิง

- [Duo Unix](https://duo.com/docs/duounix)
- [Duo Unix FAQ](https://duo.com/docs/duounix-faq)
