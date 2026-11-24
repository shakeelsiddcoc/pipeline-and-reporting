# Findings: week of 2026-10-05 (US Eastern)

Six problems. **$34,640 billed above what the data supports**, $24,000 of delivered cases with no qualification on record,
and 23 paid leads never worked. "Detected" = when the Part A monitor fired.

| # | Problem | Window | Impact | Detected |
|---|---|---|---|---|
| 1 | P3 leads missing consent certs | Wed 10-07 06:01–22:42 | 46 rejected (normal ≈3/day), acceptance 50%. ≈1.7 lost cases ≈ $5k | 10-07 10:45 |
| 2 | P2 leads verified, never routed | Thu 10-08 14:00–17:19 | 23 leads never worked; $805 paid, ≈$2.7k potential lost | 10-08 14:15 |
| 3 | B2 leads delivered twice | Fri 10-09 02:03–20:44 | 5 leads, $15,000 billed on INV008 | 10-09 02:15 |
| 4 | I1 skips the qualified step | Sat 10-10 07:58 → end of data | 18 leads; 8 signed and delivered ($24,000) unqualified | 10-10 08:15 |
| 5 | P3 calls tagged with the wrong state | All week, ongoing | 25 calls to the wrong buyer, 8 billable ($480) | 10-05 16:30 |
| 6 | Invoices don't match the data | Week's invoices | Payables +$4,640 (P1, P2); receivables +$30,000 (B1–B3) | Part C |

**1. P3 consent.** All 46 rejects have a blank `consent_cert_id`, and only P3 is affected. P3's consent capture broke for a
day; we rejected correctly and didn't pay for these leads. **Escalate:** P3 account manager. **Prevent:** a per-reject-reason rate
alert (would fire within ~1 h, not 4¾ h); notify the publisher when its acceptance is < 60% for an hour.

**2. P2 routing stall.** Other publishers routed 46 leads normally in the same window, across all states, so the problem is in
routing for P2 traffic only (config, credentials or a queue), with no retry. **Escalate:** engineering on-call; re-route the 23
leads today. **Prevent:** page on critical `stall` alerts; dead-letter queue with automatic retry.

**3. B2 duplicates.** The second delivery always comes 43–90 s after the first, in two bursts. That looks like a retry after a
timeout without idempotency. **Escalate:** delivery engineering and the B2 account manager; remove the 5 from INV008.
**Prevent:** a unique (lead, delivered) constraint; invoices count distinct leads, not events.

**4. I1 qualification.** I1's last `qualified` event is 10-09 23:46. From the next morning, retainers go straight from
`contacted`: a workflow/CRM change, or the event stopped being sent. This is a compliance risk on 8 delivered cases.
**Escalate:** I1 operations and compliance; verify those 8 before invoicing. **Prevent:** reject `retainer_sent` without `qualified`.

**5. P3 call tags.** Only P3 has mismatches (9% of its calls). It likely tags by ad targeting or IP, and we route on the tag.
**Escalate:** P3 account manager; ask B1–B3 about complaints. **Prevent:** route on the caller's actual state (ANI/geo lookup);
hold payment for mis-tagged billable calls (INV006, $480).

**6. Billing.** P1 billed all 774 received leads (698 accepted). P2 billed calls ≥ 60 s (177; billable is ≥ 90 s, 144).
Our buyer invoices counted delivery events (B2's duplicates), included next period's 10-12 deliveries, and B1 has 2 cases
not in the data. **Escalate:** finance to dispute INV001/INV005; billing engineering to correct INV007–009 before sending.
**Prevent:** build invoices from the reconciliation SQL; no invoice goes out without a clean reconciliation.
