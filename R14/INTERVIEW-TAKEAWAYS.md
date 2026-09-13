# R14 — Senior/Architect Interview Takeaways (consolidated)

**Q: What happens when your primary database fails?**
A: Detection is governed by a lease/heartbeat timeout (measured here: ~26s), not instant — instant failover on a false positive risks split-brain or an unnecessary failover, so the system deliberately waits. A replica is then promoted (real timeline increment, not just a label change), and traffic re-routes automatically.
**Key point**: "Failover isn't slow because it's broken — it's slow because instant failover on a false positive is worse than a same-minute failover on a real one."

**Q: How quickly can you recover, and how much data can you lose?**
A: These are two different guarantees measured by two different experiments here — RTO (26s live failover, 15s backup restore, 158s full cluster rebuild) and RPO (0 under healthy async replication empirically, 32 rows under an adverse network partition, 2 rows from backup-restore's WAL-archive gap, total data loss for one specific storage-class/backup-method combination).
**Key point**: "HA answers how quickly I can recover; RPO answers how much data I can afford to lose — they are not the same guarantee, and async replication only gives you the first one."

**Q: How do backups differ from HA/replication?**
A: Replication recovers quickly but needs a surviving replica. Backup restore works even with zero surviving replicas, at a much larger RTO and an RPO bounded by WAL-archive freshness, not backup frequency.
**Key point**: "Backup frequency tells you how often you copy the data; RPO tells you how much you'd actually lose — measure the second one, don't assume it equals the first."

**Q: Why choose active-passive over active-active for a relational database?**
A: Active-passive keeps writes on one node, eliminating write-write conflicts by construction; its failure mode (temporary unavailability) is easier to reason about than active-active's defining risk (silent divergence needing reconciliation).
**Key point**: "Active-passive trades write scalability for the guarantee that there is only ever one truth; active-active trades that guarantee for scale, and now you own conflict resolution."

**Q: How do you test disaster recovery properly?**
A: Destroy the real failure domain completely (this lab deleted the entire cluster, not a pod) and verify actual business data survives — not just that the restore command exited 0. The most valuable finding here was a "Completed" backup that had silently skipped the actual PV data due to a storage-class incompatibility.
**Key point**: "A 'Completed' backup status tells you the tool didn't error — it doesn't tell you your data is recoverable. Verify the data, not the exit code."

**Q: How do you avoid over-provisioning for availability?**
A: Attach a real number to the decision. This lab measured its own HA machinery (DCS + load balancer + standby) at ~4x a single instance's local memory footprint — and explicitly did NOT assume that ratio carries over to AWS's actual Multi-AZ pricing, which reflects different overhead.
**Key point**: "Every layer of HA machinery has a real, measurable resource cost — quantify it before deciding it's worth the availability it buys."

**Q: How do you know a replica is actually healthy?**
A: A lag/health metric is only as fresh as the last report from the member itself — a sufficiently unhealthy (frozen, partitioned) member can go stale rather than report a large lag number. Cross-check with an independent source.
**Key point**: "A frozen replica's dashboard doesn't say 'I'm far behind' — it just stops updating. Silence is not the same as zero lag."
