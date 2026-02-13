## 🧩 Windows Autopilot – Device Name Automation Script

### 📖 Overview

This script automates the management and update of **Windows Autopilot device names** using Microsoft Graph.  
It enables administrators to export existing Autopilot records, align devices to a defined naming convention, and apply naming at the point of enrolment.

⚠️ **Important:**  
Autopilot device naming only applies during **new device onboarding**. The name is assigned during enrolment and does not rename devices already provisioned.

---

### 🎯 Problem Statement

Many organisations onboard devices into Autopilot without enforcing a consistent naming convention.

Common challenges include:

- Inconsistent device naming across deployments
- Manual renaming processes
- Lack of visibility into current Autopilot records
- Difficulty aligning device identity with organisational standards

This script provides a repeatable and controlled approach focused specifically on enrolment-time naming.

---

### ⚙️ Key Capabilities

- Export all Autopilot devices with their current device names
- Apply naming standards via CSV input
- Status reporting for Updated, Already Named, and Failed outcomes
- Safe execution aligned to Autopilot provisioning behaviour

---

### 🛠 Technical Approach

The script:

1. Connects to Microsoft Graph with required permissions.
2. Retrieves Windows Autopilot device identities.
3. Compares existing device names against a provided CSV or naming logic.
4. Applies updates only where required.
5. Outputs structured results with status and reasoning.

---

### ⚠️ Platform Limitations

This solution follows Microsoft Autopilot behaviour and therefore:

- ✅ Device naming only applies **during enrolment**
- ❌ Does **not** rename devices that are already deployed
- ✅ Supports **Microsoft Entra joined devices only**
- ❌ Hybrid Azure AD Join scenarios are not supported for Autopilot naming

These limitations are by design and align with how Windows Autopilot processes device identity.

---

### 🔐 Security Considerations

- Requires appropriate Microsoft Graph permissions.
- Should be executed by administrators with Autopilot management rights.
- Recommended to validate against pilot devices before production use.

---

### 📦 Deployment Context

- Microsoft Intune / Windows Autopilot environments
- Enterprise or education onboarding scenarios
- Organisations implementing structured naming standards

---

### 🚀 Outcome

- Consistent device identity at onboarding
- Reduced manual renaming effort
- Improved visibility and reporting
- Scalable Autopilot naming workflow

---

**Category:** Intune | Windows Autopilot | Automation  
**Type:** PowerShell Script  
**Focus:** Device Identity & Naming Standards


