# Text Processing Pipelines

Half of Linux operations is **reading logs**. Chain grep, awk, and sed together with pipes and you can pull answers out of hundreds of thousands of log lines in seconds.

The lab environment has a 2,000-line web server access log ready. First, look at its shape.

View the first 5 lines:

```
head -5 /var/log/lab/access.log
```

Count the total lines:

```
wc -l /var/log/lab/access.log
```

The structure of one line (field numbers split on whitespace):

| Field | Content | Example |
|---|---|---|
| $1 | Client IP | `192.168.14.23` |
| $6~$8 | Request (`"METHOD path HTTP/1.1"`) | `"GET /api/users HTTP/1.1"` |
| $9 | Status code | `200` |
| $10 | Response bytes | `1532` |

## Finding errors with grep

grep is a tool that **picks out lines** matching a pattern. Let's find server errors (5xx). A naive `grep 500` also matches lines whose byte count is 500 — you must match **only the status code position**.

```
grep -E '" 5[0-9]{2} ' /var/log/lab/access.log | head
```

The key is anchoring context around the match so only a 5xx after `"` and a space qualifies. `-c` prints just the count of matching lines.

Task: save the number of 5xx error lines to `~/work/err5xx.count`.

Save the 5xx line count:

```
grep -Ec '" 5[0-9]{2} ' /var/log/lab/access.log > ~/work/err5xx.count
```

Verify the saved value:

```
cat ~/work/err5xx.count
```

Once saved, press **[Check]**.

## Field extraction and aggregation with awk

awk works on lines **split into fields**. `$1` is the first field (the IP).

```
awk '{print $1}' /var/log/lab/access.log | head
```

Attach the classic aggregation pipeline `sort | uniq -c | sort -rn` and you get a frequency table.

```
awk '{print $1}' /var/log/lab/access.log | sort | uniq -c | sort -rn
```

> `uniq -c` only counts **adjacent** duplicates, so `sort` must come first.

Task: save **only the single top IP** by request count (the IP string only, no count) to `~/work/top-ip.txt`. Take the first line with `head -1`, then extract just the IP field with awk again.

```
awk '{print $1}' /var/log/lab/access.log | sort | uniq -c | sort -rn | head -1 | awk '{print $2}' > ~/work/top-ip.txt
```

Once saved, press **[Check]**.

## Stream editing with sed

This log needs to be shared externally, but client IPs are personal data and must be **masked**. sed's substitution (`s/pattern/replacement/`) solves it.

Use a regex to catch the IPv4 at the start of each line. With `-E` (extended regex) you can use the `{1,3}` quantifier directly.

```
sed -E 's/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/REDACTED/' /var/log/lab/access.log | head -3
```

Task: save a copy of the full log with IPs replaced by `REDACTED` to `~/work/access-redacted.log`. The line count must match the original (substitution, not deletion).

Save the redacted copy:

```
sed -E 's/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/REDACTED/' /var/log/lab/access.log > ~/work/access-redacted.log
```

Count the redacted lines:

```
grep -c REDACTED ~/work/access-redacted.log
```

Once saved, press **[Check]**.

## Putting the pipeline together

The finale is a real-world question: **"What is the total bytes transferred by successful (200) responses to requests under the /api path?"**

A single awk can filter and aggregate at once — a condition selects lines, a variable accumulates, and the `END` block prints.

```
awk '$7 ~ /^\/api\// && $9 == 200 {s += $10} END {print s}' /var/log/lab/access.log
```

Broken down:

| Piece | Meaning |
|---|---|
| `$7 ~ /^\/api\//` | the path field starts with `/api` |
| `&& $9 == 200` | and the status is 200 |
| `{s += $10}` | accumulate the bytes field into s |
| `END {print s}` | print the total after reading everything |

Task: save this total to `~/work/api-bytes.txt` and press **[Check]**.

```
awk '$7 ~ /^\/api\// && $9 == 200 {s += $10} END {print s}' /var/log/lab/access.log > ~/work/api-bytes.txt
```
