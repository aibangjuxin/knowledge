Objective: Ensure that MIG instances built by Terraform operate normally, with high availability and scalability capabilities.

Steps:
	1.	Build MIG through Terraform Apply, and confirm that the number of instances created, image version, and startup scripts meet expectations.
	2.	Verify whether MIG instances pass Health Check (GCE health check or custom TCP/HTTPS).
	3.	Trigger automatic scaling scenarios (such as CPU > 90% or increased connections), verify whether new instances can be automatically created.
	4.	Manually stop one instance, verify whether it can automatically recover and maintain the expected number of instances.
	5.	Check whether there is configuration loading or service failure information in Nginx logs and system logs.

Expected Results:
	•	MIG instances come online normally, health checks pass.
	•	Automatic scaling logic takes effect.
	•	Each new instance contains the correct Nginx configuration and certificates.
	•	Failed instances can be automatically replaced without affecting overall service availability.