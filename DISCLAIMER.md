# Disclaimer

**Last updated: July 1, 2026**

This Disclaimer ("Disclaimer") governs the use of the AtomZero software project (the "Software"), including its source code, binary distributions, documentation, sample modifications, packaging tools, and any related materials (collectively, the "Project"), made available by the AtomZero contributors ("We", "Us", or "Our"). The Project is licensed under the GNU Affero General Public License v3.0 ("AGPLv3").

By installing, copying, accessing, compiling, executing, redistributing, or otherwise using any part of the Project, you ("User" or "You") acknowledge that you have read, understood, and unconditionally agreed to be bound by this Disclaimer in its entirety. If You do not agree with any provision herein, You must immediately cease all use of the Project and destroy all copies in Your possession or control.

---

## 1. Scope of Application

### 1.1 Persons Covered

This Disclaimer applies to:
- All end users who obtain, install, run, or interact with the Project in any form;
- All developers who author, modify, package, or distribute modifications ("Mods") for the Project;
- All distributors, repackagers, mirror operators, and any party that makes the Project available to others;
- All contributors who submit code, documentation, assets, or other materials to the Project.

### 1.2 Temporal Scope

This Disclaimer applies to all past, present, and future versions of the Project, including pre-release, stable, patched, and abandoned versions, unless a specific version is expressly accompanied by a superseding disclaimer. Continued use of the Project after any update to this Disclaimer constitutes acceptance of the updated version.

### 1.3 Relationship to the AGPLv3

This Disclaimer is provided in addition to, and does not supersede, replace, or limit the terms of the AGPLv3 under which the Project is licensed. In the event of any conflict between this Disclaimer and the AGPLv3, the AGPLv3 (specifically Sections 15, 16, and 17 regarding disclaimer of warranty and limitation of liability) shall prevail to the maximum extent permitted by applicable law.

### 1.4 Channel Neutrality

This Disclaimer applies regardless of the channel through which the Project is obtained, including but not limited to the official source repository, packaged release archives, third-party redistributions, derivative works, or forks.

---

## 2. Information Accuracy Statement

### 2.1 "AS IS" Provision

The Project, including its source code, documentation, comments, sample Mods, packaging tooling, API descriptions, design specifications, and any accompanying informational content, is provided on an "AS IS" and "AS AVAILABLE" basis, without any representation or warranty of any kind, whether express, implied, statutory, or otherwise.

### 2.2 No Warranties

We do not warrant, represent, or guarantee that:
- The Project will meet Your specific requirements, expectations, or intended use cases;
- The Project, or any portion of its documentation, is accurate, complete, reliable, current, or error-free;
- The Project will operate uninterrupted, secure, defect-free, or free of vulnerabilities;
- Any defects, errors, or vulnerabilities in the Project will be identified, reported, or corrected within any particular timeframe, or at all;
- The sample Mods, code examples, build scripts, or tutorials included in the Project are fit for any particular purpose, or that their execution will not produce unintended or harmful consequences;
- The technical specifications described in the documentation accurately reflect the runtime behavior of the Software in all environments.

### 2.3 Documentation Accuracy

Technical documentation and design specifications reflect Our understanding and intent at the time of authoring. They may contain inaccuracies, omissions, typographical errors, or outdated information, and may not reflect the actual behavior of the Software across all operating systems, hardware configurations, or Godot Engine versions. We reserve the right to modify, update, supplement, or remove any documentation without prior notice.

### 2.4 No Reliance

Under no circumstances shall We be liable for any decisions, actions, omissions, or inactions taken by You or any third party in reliance on the Project, its documentation, or any other content provided as part of the Project. You are solely responsible for independently verifying the accuracy, suitability, and safety of the Project for Your intended use.

---

## 3. Third-Party Content Responsibility

### 3.1 Mod Architecture

The AtomZero Project is designed as an "empty shell" architecture: the base application intentionally provides no gameplay functionality, user interface, or substantive content. All such functionality, content, and behavior are delivered through independently developed modifications ("Mods"). Mods — including but not limited to their source code, scripts, assets, configuration files, manifests, and runtime behavior — constitute third-party content over which We exercise no editorial control, no oversight, and no verification obligation.

### 3.2 No Endorsement or Certification

Inclusion of any sample Mod in the Project's repository, packaging distribution, or documentation does not constitute an endorsement, certification, recommendation, or warranty of any kind, whether express or implied. Sample Mods are provided solely for demonstration and educational purposes and may themselves contain defects, security vulnerabilities, or other limitations.

### 3.3 Allocation of Responsibility for Mods

We expressly disclaim any and all responsibility, whether direct or indirect, for:
- The functionality, performance, safety, security, legality, morality, or quality of any Mod not authored and maintained by Us;
- Any damage, loss, corruption, or harm — to data, hardware, software, finances, reputation, or otherwise — caused by Mods installed or executed by the User, regardless of the source from which such Mods were obtained;
- The behavior of Mods in interaction with the base Project, with other Mods, with the host operating system, or with any third-party service reachable from the host system;
- Any infringement or alleged infringement of intellectual property rights, privacy rights, publicity rights, or any other proprietary or personal rights committed by Mod authors, distributors, or users;
- Any malicious, illegal, harmful, defamatory, or otherwise objectionable content introduced through Mods, including but not limited to malware, ransomware, spyware, adware, exploits, data-exfiltration routines, cryptocurrency miners, or backdoors;
- The accuracy, completeness, or lawfulness of any license under which a Mod is distributed.

### 3.4 User's Due Diligence Obligation

You are solely and exclusively responsible for evaluating the trustworthiness, safety, legality, and suitability of any Mod prior to installation, execution, or distribution. In fulfilling this obligation, You should:
- Verify the cryptographic integrity of Mod packages using hashes (such as SHA-256) published by the Mod author or a trusted authority;
- Review the source code of any Mod distributed under an open-source license, with particular attention to filesystem access, network access, process spawning, and data-handling routines;
- Obtain Mods exclusively from sources You have reasonable grounds to trust, and avoid Mods of unknown or unverified provenance;
- Maintain current, tested backups of all data — including saved game states, configuration files, and Mod assets — prior to installing, updating, or removing any Mod;
- Test Mods in an isolated environment before deploying them on production or personal-use systems.

### 3.5 Best-Effort Safeguards

The Project may implement technical safeguards intended to reduce the risk of malicious or defective Mods, including but not limited to hash-based trust-on-first-use ("TOFU") verification, virtual filesystem isolation, and runtime sandboxing of Mod resources. Such safeguards are best-effort measures that cannot, and do not, guarantee protection against all threats. The absence, weakness, circumvention, or failure of any safeguard shall not, in any circumstance, give rise to liability on the part of Us, Our contributors, licensors, or affiliates.

---

## 4. Risk Warnings

### 4.1 Inherent Risks of Use

Use of the Project — including but not limited to running the base Software, installing Mods, authoring Mods, and redistributing the Project — involves inherent and unavoidable risks. You acknowledge and accept, without reservation, the following categories of risk:

- **Data Loss or Corruption**: The Project reads, writes, and modifies user-generated data, including saved game states and Mod configuration. Software defects, Mod conflicts, power failures, filesystem errors, or improper shutdowns may result in data loss, corruption, inaccessibility, or unintended disclosure.
- **System Instability**: Mods execute within the Project's runtime process and may introduce instability, crashes, hangs, performance degradation, memory leaks, or conflicts with the host operating system, drivers, or other software.
- **Security Risks**: Mods execute with the privileges of the Project process and may, intentionally or unintentionally, read, write, delete, modify, or transmit files and data on the host system or any accessible network service. There is no guarantee, express or implied, that the Project's isolation mechanisms will prevent all unauthorized access or harmful behavior.
- **Hardware Impact**: Certain Mods may stress system resources — including CPU, GPU, memory, secondary storage, and thermal management systems — and, in extreme or sustained cases, may contribute to hardware degradation, failure, or accelerated wear, particularly on systems with pre-existing conditions or inadequate cooling.
- **Privacy Risks**: Mods may collect, store, transmit, or sell personal, behavioral, or system information without Your knowledge or consent. We do not audit Mod behavior, do not perform privacy reviews, and cannot ensure the confidentiality or integrity of Your data when third-party Mods are installed.
- **Compatibility Risks**: Future versions of the Project may introduce breaking changes to APIs, file formats, or Mod manifests. Mods compatible with one version may cease to function, may function incorrectly, or may cause damage when run against other versions of the Project.

### 4.2 High-Risk Use Prohibition

The Project is not designed, certified, intended, or authorized for use in high-risk activities or in any application where the failure of the Software could reasonably be expected to lead to personal injury, death, or catastrophic environmental or property damage, including but not limited to:
- Medical devices, diagnostic systems, or healthcare applications;
- Automotive, aerospace, aviation, maritime, or rail systems;
- Nuclear facilities, power generation or distribution infrastructure;
- Industrial control systems, manufacturing equipment, or robotics;
- Military, defense, or public-safety systems;
- Financial trading, clearing, or settlement infrastructure where errors could cause systemic loss.

Any such use is strictly at Your own risk, is explicitly discouraged, and is not supported by Us in any manner.

### 4.3 User Responsibility for Risk Mitigation

You are responsible for implementing appropriate, proportional risk-mitigation measures appropriate to Your use case, including but not limited to:
- Maintaining current, tested, and redundant backups of all critical data;
- Running the Project in an isolated, sandboxed, or non-production environment when testing untrusted or newly installed Mods;
- Restricting the Project's filesystem, network, and peripheral access through operating-system-level controls (such as containerization, mandatory access control, or application firewalls) where appropriate;
- Reviewing the source code and runtime behavior of any Mod before installation;
- Keeping the host operating system, drivers, runtime libraries, and security software fully patched and up to date;
- Monitoring system behavior, resource usage, and network activity when running unfamiliar Mods.

### 4.4 Non-Exhaustive Enumeration

The risks enumerated in this Section 4 are illustrative and are not intended to be exhaustive. Additional risks — whether currently known, unknown, unforeseeable, or arising from future technological, legal, or operational developments — may exist. You assume all risks associated with Your use of the Project, whether or not such risks are expressly identified herein, and whether or not We were or should have been aware of them.

---

## 5. Limitation of Liability

### 5.1 General Limitation

To the maximum extent permitted by applicable law, in no event shall We, Our contributors, licensors, affiliates, officers, directors, employees, agents, or successors (collectively, the "Protected Parties") be liable for any:
- Direct, indirect, incidental, consequential, special, exemplary, incidental, or punitive damages;
- Loss of profits, revenue, business, contracts, anticipated savings, or goodwill;
- Loss of, corruption of, or unauthorized access to data;
- Business interruption, system downtime, or loss of productivity;
- Cost of procurement of substitute goods, services, or software;
- Damage to hardware, firmware, software, networks, or data;
- Any other commercial, financial, or non-financial damage or loss;

arising out of or in any way connected with the use of, inability to use, performance of, reliance on, or distribution of the Project, whether based on contract, tort (including negligence), strict liability, breach of warranty, or any other legal theory, and whether or not the relevant Protected Party has been advised of the possibility of such damages.

### 5.2 Aggregate Cap

The aggregate liability of all Protected Parties for all claims arising from or relating to the Project, regardless of form of action, shall not exceed the total amount actually paid by You to any Protected Party for the Project during the twelve (12) months immediately preceding the event giving rise to the claim. As the Project is distributed free of charge and without consideration, this cap shall in all cases be zero (USD $0.00).

### 5.3 Mandatory Law Exceptions

Where applicable law — including mandatory consumer protection legislation — prohibits the exclusion or limitation of certain liabilities or confers non-waivable rights upon consumers, nothing in this Disclaimer shall be construed to override such mandatory provisions. In such jurisdictions, the liability of the Protected Parties shall be limited to the minimum extent necessary to comply with applicable mandatory law.

---

## 6. Intellectual Property

The Project is licensed exclusively under the AGPLv3. All rights not expressly granted under the AGPLv3 are reserved by the respective copyright holders. Nothing in this Disclaimer shall be construed as granting, by implication, estoppel, or otherwise, any license or right to any intellectual property owned by any Protected Party, except as expressly set forth in the AGPLv3.

Mods distributed as part of the Project, including sample Mods, are subject to their respective licenses as indicated in their `mod.json` manifest files and accompanying documentation. We make no representation or warranty regarding the validity, scope, ownership, or enforceability of any third-party Mod license, and expressly disclaim any liability arising from Mod licensing disputes between You and any third party.

---

## 7. Governing Law and Jurisdiction

### 7.1 Governing Law

This Disclaimer, and any dispute, claim, or controversy arising out of or in connection with it or the use of the Project, shall be governed by and construed in accordance with the laws of the jurisdiction in which the Project's primary copyright holder is domiciled, without regard to its conflict-of-law provisions.

### 7.2 Informal Dispute Resolution

In the event of any dispute, controversy, or claim arising out of or relating to this Disclaimer or the use of the Project, the parties shall first attempt in good faith to resolve the dispute through informal negotiation. If the dispute cannot be resolved through such negotiation within thirty (30) calendar days, the parties shall submit the dispute to non-binding mediation administered by a mutually agreed mediator or recognized mediation institution.

### 7.3 Arbitration

Any dispute that cannot be resolved through the procedures described in Section 7.2 shall be finally resolved by binding arbitration, conducted in the English language, in accordance with the rules of an internationally recognized arbitration institution agreed upon by the parties. The seat of arbitration shall be the jurisdiction identified in Section 7.1. The arbitral award shall be final and binding upon both parties, and judgment thereon may be entered in any court of competent jurisdiction.

### 7.4 Jurisdictional Fallback

Subject to the foregoing provisions, and without prejudice to any party's right to seek interim or injunctive relief from a court of competent jurisdiction, the courts of the jurisdiction identified in Section 7.1 shall have exclusive jurisdiction over any matter arising under this Disclaimer that cannot be resolved through alternative dispute resolution.

### 7.5 Mandatory Consumer Rights

Where You are a consumer protected by mandatory consumer protection laws of Your jurisdiction of residence, those laws may grant You rights that cannot be waived, including rights to bring proceedings in Your local courts. Nothing in this Section 7 shall be construed to deprive You of any such non-waivable rights.

---

## 8. International Use and Export Compliance

### 8.1 International Distribution

The Project is distributed internationally via the internet. We make no representation that the Project is appropriate, lawful, or available for use in all jurisdictions. Users who access or download the Project from locations outside the primary distribution jurisdiction do so on their own initiative and are responsible for compliance with all applicable local laws.

### 8.2 Export Control and Sanctions

You represent and warrant that You are not:
- Located in, organized under the laws of, or ordinarily resident in a country or territory subject to comprehensive economic sanctions or embargoes administered by the United Nations, the European Union, the United States, the United Kingdom, or any other competent authority;
- Listed on any restricted-party or denied-persons list maintained by any such authority;
- Engaged, directly or indirectly, in any activity that would cause the distribution of the Project to violate any applicable export control, trade sanction, or anti-boycott law.

You agree not to export, re-export, transfer, or make available the Project, in whole or in part, in violation of any applicable export control or sanctions regime.

### 8.3 Data Protection and Privacy

Users are solely responsible for compliance with all applicable data protection and privacy laws in their jurisdiction, including, where applicable, the European Union General Data Protection Regulation (Regulation (EU) 2016/679, the "GDPR"), the California Consumer Privacy Act ("CCPA"), and equivalent legislation in other jurisdictions. We do not act as a data controller or processor with respect to Your use of the Project, and we do not collect personal data through the Project itself.

### 8.4 Cryptographic Software

Some jurisdictions restrict the use, export, or distribution of cryptographic software. If the Project or any Mod incorporates cryptographic functionality, You are responsible for ensuring compliance with all applicable laws governing such software in Your jurisdiction.

---

## 9. Modifications to this Disclaimer

### 9.1 Right to Modify

We reserve the right to modify, update, supplement, or replace this Disclaimer at any time, in Our sole discretion, without prior notice to Users. The "Last updated" date indicated at the top of this document reflects the most recent revision.

### 9.2 Effectiveness of Changes

Modified versions of this Disclaimer become effective immediately upon publication in the official Project repository. Continued use of the Project after any modification constitutes Your unconditional acceptance of the updated Disclaimer.

### 9.3 User's Duty to Review

It is Your responsibility to periodically review this Disclaimer for changes. Your sole and exclusive remedy in the event of disagreement with any modified Disclaimer is to cease all use of the Project and to destroy all copies in Your possession or control.

---

## 10. Severability

If any provision of this Disclaimer is held by a court, tribunal, or arbitral body of competent jurisdiction to be invalid, illegal, void, or unenforceable, such provision shall be modified to the minimum extent necessary to make it valid, legal, and enforceable while preserving the original intent of the parties to the maximum extent possible. If such modification is not possible, the affected provision shall be severed from this Disclaimer, and the remaining provisions shall continue in full force and effect to the maximum extent permitted by applicable law.

---

## 11. No Waiver

No failure, delay, or omission on the part of any Protected Party to exercise any right, power, or privilege under this Disclaimer shall operate as, or be construed as, a waiver of such right, power, or privilege. No single or partial exercise of any right, power, or privilege shall preclude any other or further exercise thereof or the exercise of any other right. No waiver shall be effective against any Protected Party unless it is in writing and signed by an authorized representative of that party.

---

## 12. Entire Agreement

This Disclaimer, together with the AGPLv3 license under which the Project is distributed and any referenced policies explicitly incorporated by reference, constitutes the entire agreement between You and Us with respect to the subject matter herein and supersedes all prior or contemporaneous understandings, communications, representations, or agreements, whether oral or written, regarding such subject matter.

---

## 13. Assignment

You may not assign, transfer, delegate, or sublicense Your rights or obligations under this Disclaimer, in whole or in part, without Our prior written consent. Any attempted assignment in violation of this Section 13 shall be null and void. We may assign this Disclaimer, in whole or in part, without restriction.

---

## 14. Contact

For questions, clarifications, or formal notices regarding this Disclaimer, please contact the Project maintainers through the official source repository's issue tracker or via the contact information published in the Project's `README.md` file. Notices sent by electronic means shall be deemed received upon successful transmission; notices requiring physical delivery shall be deemed received upon actual receipt.

---

*By using the AtomZero Project, in any form or capacity, You acknowledge that You have read, understood, and agreed to be bound by this Disclaimer in its entirety. If You do not agree, You are not authorized to use the Project in any manner.*
