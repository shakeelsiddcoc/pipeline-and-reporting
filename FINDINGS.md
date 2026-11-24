# Findings: week of 2026-10-05 (US Eastern)

Seven problems. **$34,640 billed above what the data supports**, $24,000 of delivered cases with no qualification on record,
and 23 paid leads never worked. "Detected" = when the Part A monitor fired.

| # | Problem | Window | Impact | Detected |
|---|---|---|---|---|
| 1 | P3 leads missing consent certs | Wed 10-07 06:01–22:42 | 46 rejected (normal ≈3/day), acceptance 50%. ≈1.7 lost cases ≈ $5k | 10-07 10:30 |
| 2 | P2 leads verified, never routed | Thu 10-08 14:00–17:19 | 23 leads still unrouted at end of data (backlog); $805 paid, ≈$2.7k potential lost | 10-08 14:15 |
| 3 | B2 leads delivered twice | Fri 10-09 02:03–20:44 | 5 leads, $15,000 billed on INV008 | 10-09 02:15 |
| 4 | I1 skips the qualified step | Sat 10-10 07:58 → end of data | 18 leads; 8 signed and delivered ($24,000) unqualified | 10-10 08:15 |
| 5 | P3 calls tagged with the wrong state | All week, ongoing | 25 calls to the wrong buyer, 8 billable ($480) | 10-05 16:30 |
| 6 | Invoices don't match the data | Week's invoices | Payables +$4,640 (P1, P2); receivables +$30,000 (B1–B3) | Part C |
| 7 | P1 sent no calls | Wed 10-07 08:40–11:10 | ≈7 expected calls missing, ≈3 billable (≈$180) | 10-07 10:45 |

**1. P3 consent.** All 46 rejects have a blank `consent_cert_id`; only P3 is affected, so P3's consent capture broke. We
rejected correctly and didn't pay. **Escalate:** P3 account manager. **Prevent:** a per-reject-reason alert (≈1 h to detect, not 4½ h).

**2. P2 routing stall.** Other publishers routed 46 leads normally in the same window, across all states: routing broke for P2
traffic only, with no retry. **Escalate:** engineering on-call; re-route the 23 backlog leads today. **Prevent:** page on critical
`stall`; dead-letter queue with retry.

**3. B2 duplicates.** Each repeat comes 43–90 s after the first delivery, in two bursts: a timeout retry without idempotency.
**Escalate:** delivery engineering, B2 account manager; remove the 5 from INV008. **Prevent:** unique (lead, delivered); invoice distinct leads.

**4. I1 qualification.** I1's last `qualified` event is 10-09 23:46. From the next morning, retainers go straight from
`contacted`: a workflow/CRM change, or the event stopped being sent. This is a compliance risk on 8 delivered cases.
**Escalate:** I1 operations and compliance; verify those 8 before invoicing. **Prevent:** reject `retainer_sent` without `qualified`.

**5. P3 call tags.** Only P3 has mismatches (9% of its calls); it likely tags by ad targeting or IP, and we route on the tag.
**Escalate:** P3 account manager; ask B1–B3 about complaints. **Prevent:** route on the caller's state (ANI lookup); hold INV006's $480.

**6. Billing.** P1 billed all 774 received leads (698 accepted). P2 billed calls ≥ 60 s (177; billable is ≥ 90 s, 144).
Our buyer invoices counted delivery events (B2's duplicates), included next period's 10-12 deliveries, and B1 has 2 cases
not in the data. Those 2 may be lost delivery events rather than an invoice error, which would mean we under-bill.
**Escalate:** finance to dispute INV001/INV005; billing engineering to correct INV008–009; engineering to check B1's delivery logs before INV007 is corrected.
**Prevent:** build invoices from the reconciliation SQL; no invoice goes out without a clean reconciliation.

**7. P1 call gap.** No P1 calls for 2½ h when this time of day averages ≈7 (≈0.1% chance if random); the only daytime gap all week,
and it recovered by itself. Likely a call-tracking outage at P1. **Escalate:** P1 account manager. **Prevent:** the `silence` check fires on it.

*Checked, nothing found:* call connect rates (0.64–0.89/day), duplicate leads by `phone_hash`, non-`success` events, leads delivered to two buyers.
5 calls are `connected` with 0 s duration: no money impact, but a flag for the call tracker.
