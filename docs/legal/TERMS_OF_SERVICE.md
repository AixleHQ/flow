# Aixle Flow Terms of Service

**Last updated:** August 6, 2026 · **Effective:** August 6, 2026

## 1. Agreement and Parties

These Terms of Service ("Terms") govern access to and use of the hosted Aixle Flow service ("Service") provided by Dualboot Partners, LLC ("Dualboot," "we," "us"), 5540 Centerview Dr., Ste. 204, #24754, Raleigh, NC 27606.

By creating an account, accessing the Service, or agreeing to these Terms on behalf of an organization, you accept them. If you accept on behalf of an organization, you represent that you are authorized to bind it, and "you" and "Customer" refer to that organization.

## 2. Relationship to the Open-Source License

The software underlying the Service is made available separately under the Apache License, Version 2.0. These Terms govern only our provision of the hosted Service.

Nothing in these Terms limits any right granted to you under the Apache License 2.0 in respect of the source code, including the rights to use, modify, and redistribute it, and to operate your own deployment for any purpose. Our trademarks are not licensed by the Apache License or by these Terms; their use is governed by our trademark policy.

If you obtained the software directly (for example, via a public repository) rather than through the hosted Service, your use of that software is governed solely by the Apache License and any accompanying NOTICE file, not by these Terms.

## 3. Accounts and Access

**3.1** Access requires authentication through a supported identity provider (we support Google OpenID Connect) or, where we have enabled it for your organization, a password credential issued through your organization account. You are responsible for your users' credentials and for all activity under your organization's account.

**3.2** You control who you invite to your organization and what role each user holds. Roles are Employee and Admin, with different privileges.

**3.3** Your organization account is associated with an email domain. Where automatic acceptance is enabled for your organization, any person who authenticates with an email address in that domain joins your organization without individual approval, and thereby obtains the access described in Section 6.1. You are responsible for deciding whether that configuration is appropriate for your organization and for control of your email domain.

**3.4** You must notify us promptly of any suspected unauthorized access.

**3.5** Our operational staff may access your account, sessions, and session records where necessary to provide, secure, support, or troubleshoot the Service. Such access is subject to Section 10 (Confidentiality) and to our Privacy Policy.

## 4. Customer Data

**4.1 Definition.** "Customer Data" means all data you or your users submit to, or that the Service generates, collects, or captures on your behalf in the course of providing the Service — including instructions and prompts submitted to agents; source code and repository contents retrieved from your connected source-control systems; files, artifacts, and assets created, modified, or uploaded during a session; agent session transcripts and container logs, including logs of traffic between an agent and the AI provider it is configured to use; board, task, workflow, and comment content; payloads received from your connected systems by webhook; usage and cost records; and user records. The categories are described in the Privacy Policy.

**4.2 Ownership.** You retain all right, title, and interest in Customer Data. We claim no ownership.

**4.3 Our license.** You grant us a limited, non-exclusive license to host, store, process, and transmit Customer Data solely to provide, secure, and support the Service, and as instructed by you. We do not use Customer Data for any other purpose.

**4.4 No use for model training.** We do not use Customer Data — including instructions, source code, or session transcripts — to train machine-learning models, and we do not disclose it to third parties for that purpose.

**4.5 Your responsibilities.** You are responsible for ensuring you have the legal right and any necessary basis, notices, and permissions to submit Customer Data to the Service and to grant us access to the systems you connect, including the right to submit any source code or third-party material processed in a session, and including as set forth in Section 6 with respect to visibility of individual usage by your personnel.

**4.6 Sensitive data.** The Service is not designed for, and you must not knowingly submit, special-category personal data, payment-card data, regulated health data, or any other regulated data class. You acknowledge that instructions, repository contents, and session transcripts are captured as submitted by your users or as produced by an agent, and that we cannot filter them.

## 5. Agent Execution, Connected Credentials, and Customer Environments

**5.1 What the Service does.** The Service launches AI coding agents in isolated containers that we operate, injects the context you configure (repositories, MCP servers, tools, skills, assets, and configuration), and runs those agents on your instructions. Depending on how you configure a session or workflow, an agent may operate autonomously, without step-by-step human confirmation of individual actions.

**5.2 Credentials and systems you connect.** You may connect source-control accounts and installations, issue trackers, messaging and infrastructure providers, MCP servers, and AI-assistant accounts. You determine what you connect and the scope of the permissions you grant, which may include write access to your repositories. We store connected credentials in encrypted form and use them only to operate sessions you or your users initiate. You are responsible for the scope of access you grant, for keeping it current, and for revoking it when it is no longer required.

**5.3 AI-assistant accounts and provider terms.** A session authenticates to the AI provider using credentials your user onboards through the Service — typically that user's own account with, or API key for, that provider. The provider's own terms and privacy practices govern the provider's processing of anything the agent sends to it. You and your users are responsible for holding the rights necessary to use those accounts in an automated, server-hosted environment and for compliance with any applicable provider limits or restrictions. We are not a party to that relationship, do not resell provider capacity, and make no representation about a provider's processing of that content.

**5.4 Actions taken by agents.** Within the permissions you grant, an agent may read, create, modify, and delete files in its container; execute commands and install dependencies; make outbound network requests; invoke MCP tools and connected integrations; and read from and write to your connected source-control systems. Actions taken using credentials you connected are treated as taken by you, whether or not a user directed the specific action. We do not review agent actions before they occur and do not control what an agent decides to do in response to your instructions.

**5.5 Human review.** You are responsible for reviewing agent output before merging, deploying, or otherwise relying on it. The Service provides approval gates in workflows and artifact review; whether you use them is your decision.

**5.6 No warranty as to output.** Output produced by an agent may be inaccurate, incomplete, insecure, non-functional, or substantially similar to third-party material. We make no representation or warranty that output is correct, original, fit for any purpose, or free of third-party rights, and you are responsible for any testing, security review, and license-compliance review before using it. This Section 5.6 is without limitation to Section 11.

**5.7 Containers are ephemeral.** A session's container and its filesystem are destroyed when the session ends. Only artifacts that the Service collects and stores persist. You are responsible for ensuring that work you wish to keep is committed to a connected repository or exported before a session ends.

## 6. Visibility of Individual Usage and Personnel Monitoring

**6.1 What the Service records and who can see it.** The Service records, for each session, the user who initiated it, the instruction submitted, the agent and model used, token counts, computed cost, duration, and the artifacts produced. Any member of your organization account can view sessions and usage records for your organization, including sessions initiated by other users and the instructions submitted with them. Complete session transcripts and container logs are retained by the Service as described in the Privacy Policy.

**6.2 Customer's Sole Responsibility.** The Service allows Customer to monitor, log, or review individual usage by Customer's personnel, including instructions and session content attributable to specific individuals. As between the parties, Customer is solely responsible for determining whether such monitoring is lawful in each jurisdiction in which Customer's personnel are located, and for obtaining and maintaining any legal basis, notice, consent, works council or employee-representative consultation, or regulatory approval that Applicable Law requires before enabling or using such functionality.

**6.3 Representation and Warranty.** Customer represents and warrants that, before enabling monitoring of any individual's usage of the Service, Customer has completed any notice, consultation, or approval process required by Applicable Law in the relevant jurisdiction, including any consultation with or approval from a works council, employee representative body, or similar entity where such consultation or approval is a legal prerequisite to implementing the monitoring. Customer will promptly notify Company if it becomes aware that this representation is or becomes inaccurate.

**6.4 No Assumption of Customer's Obligations.** Company provides the Service, including any monitoring functionality, on Customer's instructions as controller. Nothing in this Section or these Terms shifts to Company any obligation to provide notice to, or obtain consent, consultation, or approval from, Customer's personnel or their representatives, and Company makes no independent determination as to the legality of Customer's use of monitoring functionality in any jurisdiction.

**6.5 Indemnification.** Without limiting Section 13, Customer will indemnify, defend, and hold harmless Company from and against any claims, damages, liabilities, fines, regulatory actions, or expenses (including reasonable attorneys' fees) arising from or relating to Customer's failure to satisfy any notice, consent, consultation, or approval requirement described in this Section, including any claim brought by an employee, employee representative body, works council, or regulator arising from Customer's use of the Service in violation of Applicable Law.

**6.6 Available Controls.** Company makes available controls over organization membership, automatic acceptance of users by email domain, project membership, and which users may initiate sessions. Customer is responsible for configuring the Service consistent with the outcome of its own legal assessment under this Section.

## 7. Free Tier and Quotas

The Service is currently provided free of charge. Company may establish, modify, or remove usage limits, rate limits, compute and storage quotas, or session concurrency limits for the free tier at any time, with such changes taking effect upon posting or by other reasonable notice. We reserve the right to introduce paid tiers or modify the scope of the free offering in the future, with reasonable advance notice for material changes affecting existing Customers.

## 8. Acceptable Use

You must not, and must not permit your users to:

**(a)** access the Service other than through the interfaces we provide, or circumvent rate limits, quotas, or access controls;
**(b)** use the Service to store or transmit unlawful, infringing, or malicious content;
**(c)** attempt to gain unauthorized access to the Service, other customers' data, or our infrastructure;
**(d)** interfere with or disrupt the integrity or performance of the Service;
**(e)** resell, sublicense, or offer the hosted Service (as distinct from the underlying open-source software, which may be freely used, modified, and hosted by anyone under the Apache License 2.0) to third parties as a competing hosted or managed offering, or use our trademarks in connection with any such offering, except as separately agreed with us in writing;
**(f)** use the container execution capabilities of the Service to mine cryptocurrency, to run workloads unrelated to the operation of agents on your own projects, or otherwise to consume compute, storage, or network resources abusively;
**(g)** use a session, its network access, or a connected integration to scan, probe, attack, or send unsolicited communications to any system you are not authorized to access;
**(h)** attempt to escape, disable, or circumvent the isolation of a container, or to access the containers, namespaces, credentials, or data of another user or customer;
**(i)** submit source code or other content you do not have the right to submit, or use the Service in a manner that breaches the terms of an AI provider or other third-party system you connect to it.

## 9. Availability and Support

As of the Effective Date, we do not offer a service-level agreement or uptime commitment for the Service. Sessions and their containers are ephemeral, and we make no commitment to preserve the state of a running session; see Section 5.7.

Community support for the open-source project (for example, GitHub issues and discussions) is provided on a best-efforts, volunteer basis and is not a contractual support commitment for the hosted Service.

## 10. Confidentiality

**10.1** Each party may receive from the other information that is designated confidential or that reasonably should be understood to be confidential given the nature of the information and the circumstances of disclosure ("Confidential Information"). Confidential Information does not include Customer Data, which is addressed exclusively in Section 4.

**10.2** Each party will use the other party's Confidential Information solely to exercise its rights and perform its obligations under these Terms, will protect it using at least the same degree of care it uses for its own confidential information of a similar nature (and in no event less than a reasonable degree of care), and will not disclose it to any third party except to employees, contractors, and advisors who need to know it and are bound by confidentiality obligations at least as protective as those in this Section.

**10.3** These obligations do not apply to information that: (a) is or becomes publicly available through no fault of the receiving party; (b) was rightfully known to the receiving party before disclosure; (c) is rightfully received from a third party without a duty of confidentiality; or (d) is independently developed without use of the disclosing party's Confidential Information.

**10.4** A party may disclose Confidential Information to the extent required by Applicable Law or legal process, provided it gives the other party prompt notice of the requirement (where legally permitted) so that the other party may seek a protective order or other appropriate remedy.

## 11. Warranties and Disclaimers

**11.1** THE SERVICE AND ANY ASSOCIATED SOFTWARE ARE PROVIDED "AS IS" AND "AS AVAILABLE," WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS, IMPLIED, OR STATUTORY, INCLUDING WITHOUT LIMITATION ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT, AND ANY WARRANTIES ARISING OUT OF COURSE OF DEALING OR USAGE OF TRADE. WE DO NOT WARRANT THAT THE SERVICE WILL BE UNINTERRUPTED, ERROR-FREE, OR SECURE.

**11.2** This Section 11 governs only the hosted Service. It does not apply to, limit, or expand the warranty disclaimer in Section 7 of the Apache License, Version 2.0, which applies independently and solely to the underlying source code licensed thereunder.

**11.3** Without limiting Section 11.1, we give no warranty as to output produced by an agent, or as to the actions an agent takes in your systems; see Sections 5.4 and 5.6.

## 12. Limitation of Liability

**12.1** EXCEPT FOR DAMAGES RESULTING FROM A PARTY'S GROSS NEGLIGENCE, WILLFUL MISCONDUCT, OR FRAUD, OR AS OTHERWISE PROVIDED IN AN AGREEMENT BETWEEN DUALBOOT AND YOU, TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, DUALBOOT SHALL NOT BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS, REVENUE, DATA, OR GOODWILL, ARISING OUT OF OR RELATED TO THESE TERMS OR THE SERVICE, REGARDLESS OF THE THEORY OF LIABILITY, EVEN IF SUCH PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

**12.2** This Section 12 governs only liability arising from the hosted Service under these Terms. It does not apply to, limit, or expand the limitation of liability in Section 8 of the Apache License, Version 2.0, which applies independently and solely to claims relating to the licensed source code.

## 13. Indemnification

**13.1 By Customer.** Customer will indemnify, defend, and hold harmless Company from and against any claims, damages, liabilities, and expenses (including reasonable attorneys' fees) arising from: (a) Customer Data, including any claim that our receipt, storage, or processing of Customer Data in accordance with these Terms infringes, misappropriates, or violates the rights of any third party; (b) Customer's or its users' use of the Service in violation of these Terms or Applicable Law; (c) Customer's breach of Section 4 (Customer Data) or Section 5 (Agent Execution, Connected Credentials, and Customer Environments); (d) any action taken by an agent using credentials or access Customer or its users connected to the Service, and Customer's use of, deployment of, or reliance on output produced by an agent, including any claim that such output infringes or misappropriates the rights of any third party; or (e) any claim by an AI provider or other third party arising from the use of an account or credential Customer or its users connected to the Service.

**13.2** The indemnified party will provide prompt written notice of any claim, allow the indemnifying party to control the defense and settlement (provided any settlement imposing liability or obligations on the indemnified party requires its prior written consent, not to be unreasonably withheld), and provide reasonable cooperation at the indemnifying party's expense.

## 14. Term and Termination

**14.1** These Terms remain in effect for as long as you maintain an account or otherwise access the Service, unless earlier terminated as set out below.

**14.2** Either party may terminate these Terms for convenience upon notice.

**14.3** We may suspend or terminate your access to the Service at any time, with or without cause, where not prohibited by Applicable Law. Upon termination: (a) your right to access the Service ends; (b) Company has no obligation to retain, and may immediately and without notice delete, any data, content, or information associated with your account, including session records, transcripts, and artifacts. You are solely responsible for exporting or backing up any data you wish to retain prior to termination. Company disclaims all liability for any data unavailability or deletion following termination; and (c) termination of the hosted Service does not affect any rights previously granted to you under the Apache License 2.0 with respect to source code you have already obtained.

**14.4** Sections 4 (solely as to Customer Data not yet deleted or returned), 5, 6, 10–13, and 17–18 survive termination.

## 15. Suspension

**15.1** We may suspend your (or any user's) access to all or part of the Service, without liability, if: (a) we reasonably believe your use presents a security risk to the Service or other customers; (b) your use violates Section 8 (Acceptable Use); (c) suspension is required to comply with Applicable Law or a governmental request; or (d) continued provision of the Service to you would, in our reasonable judgment, expose us to material legal or regulatory risk.

**15.2** Where reasonably practicable and not prohibited by Applicable Law, we will provide advance notice of a suspension and the reason for it. We will restore access promptly once the circumstance giving rise to the suspension is resolved.

**15.3** Suspension under this Section does not itself terminate these Terms, and Sections 4, 5, 6, and 10–19 continue to apply during any period of suspension.

## 16. Changes to the Service or Terms

We may modify the Service or these Terms at any time. We will provide reasonable advance notice of material changes to these Terms (for example, by email or an in-app notice) before they take effect. Continued use of the Service after a change takes effect constitutes acceptance of the revised Terms; if you do not agree, you must stop using the Service and may terminate your account in accordance with Section 14.

## 17. Governing Law and Disputes

These Terms are governed by the laws of North Carolina, without regard to its conflict-of-laws principles. Any dispute arising out of or relating to these Terms or the Service will be resolved exclusively in the state or federal courts located in North Carolina, and each party consents to the exclusive jurisdiction of such forum.

## 18. General

**18.1 Severability.** If any provision of these Terms is found unenforceable, the remaining provisions remain in full force and effect.

**18.2 Entire agreement.** These Terms, together with the Apache License 2.0 (as applicable to the licensed source code) and our Privacy Policy, constitute the entire agreement between you and us regarding the Service, and supersede any prior agreements regarding the Service.

**18.3 No waiver.** Failure to enforce any provision is not a waiver of that provision.

**18.4 Assignment.** You may not assign or transfer these Terms without our prior written consent; we may assign these Terms without restriction, including in connection with a merger, acquisition, or sale of assets.

**18.5 Relationship of the parties.** Nothing in these Terms creates a partnership, joint venture, agency, or employment relationship between the parties.

## 19. Contact

Questions about these Terms should be directed to Dualboot Partners, LLC, 5540 Centerview Dr., Ste. 204, #24754, Raleigh, NC 27606, or by email to legal@aixle.com.
