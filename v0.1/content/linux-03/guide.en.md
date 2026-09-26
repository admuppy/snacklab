# Text Processing Pipelines

Half of Linux operations is **reading logs**. Chain grep, awk, and sed together with pipes and you can pull answers out of hundreds of thousands of log lines in seconds.

The lab environment has a 2,000-line web server access log ready. First, look at its shape.

View the first 5 lines:

```
head -5 /var/log/lab/access.log
```

- `head -5 <file>` — prints only the first 5 lines (same as `-n 5`).

Count the total lines:

```
wc -l /var/log/lab/access.log
```

- `wc -l <file>` — counts lines (word count, line mode); `-w` counts words, `-c` bytes.

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

- `grep -E` — extended regex; `5[0-9]{2}` is a three-digit number starting with 5.
- `'" 5[0-9]{2} '` — the surrounding quote and spaces pin the match to the status-code position. The whole pattern is single-quoted so the shell leaves it alone.

The key is anchoring context around the match so only a 5xx after `"` and a space qualifies. `-c` prints just the count of matching lines.

Task: save the number of 5xx error lines to `~/work/err5xx.count`.

Save the 5xx line count:

```
grep -Ec '" 5[0-9]{2} ' /var/log/lab/access.log > ~/work/err5xx.count
```

- `-c` — print the **count** of matching lines instead of the lines; combined with `-E` as `-Ec`.
- `> ~/work/err5xx.count` — saves that number to a file.

Verify the saved value:

```
cat ~/work/err5xx.count
```

- `cat` — prints the file to confirm the saved number.

Once saved, press **[Check]**.

## Field extraction and aggregation with awk

awk works on lines **split into fields**. `$1` is the first field (the IP).

```
awk '{print $1}' /var/log/lab/access.log | head
```

- `awk '{print $1}'` — splits each line into whitespace-separated fields and prints the first (the IP). The action inside `{ }` runs for every line.

Attach the classic aggregation pipeline `sort | uniq -c | sort -rn` and you get a frequency table.

```
awk '{print $1}' /var/log/lab/access.log | sort | uniq -c | sort -rn
```

- `sort` — groups identical IPs together; `uniq -c` — collapses consecutive duplicates and prefixes the count.
- `sort -rn` — numeric (`-n`) reverse (`-r`) sort → the busiest IP on top.

> `uniq -c` only counts **adjacent** duplicates, so `sort` must come first.

Task: save **only the single top IP** by request count (the IP string only, no count) to `~/work/top-ip.txt`. Take the first line with `head -1`, then extract just the IP field with awk again.

```
awk '{print $1}' /var/log/lab/access.log | sort | uniq -c | sort -rn | head -1 | awk '{print $2}' > ~/work/top-ip.txt
```

- `head -1` — keep the top line (`  123 1.2.3.4`).
- `awk '{print $2}'` — take its second field (the IP) and save it with `>`.

Once saved, press **[Check]**.

## Stream editing with sed

This log needs to be shared externally, but client IPs are personal data and must be **masked**. sed's substitution (`s/pattern/replacement/`) solves it.

Use a regex to catch the IPv4 at the start of each line. With `-E` (extended regex) you can use the `{1,3}` quantifier directly.

```
sed -E 's/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/REDACTED/' /var/log/lab/access.log | head -3
```

- `sed -E 's/pattern/replacement/'` — replaces the first match on each line and prints the result (the file itself is unchanged).
- `^` — start of line, `[0-9]{1,3}` — 1–3 digits, `\.` — a literal dot; together, the IPv4 address at the start of the line.

Task: save a copy of the full log with IPs replaced by `REDACTED` to `~/work/access-redacted.log`. The line count must match the original (substitution, not deletion).

Save the redacted copy:

```
sed -E 's/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/REDACTED/' /var/log/lab/access.log > ~/work/access-redacted.log
```

- Applies the same substitution to the whole file and saves a new copy. `-i` would edit the original in place, but here we keep it.

Count the redacted lines:

```
grep -c REDACTED ~/work/access-redacted.log
```

- Counts lines containing `REDACTED`; it should equal the original line count from `wc -l`.

Once saved, press **[Check]**.

## Putting the pipeline together

The finale is a real-world question: **"What is the total bytes transferred by successful (200) responses to requests under the /api path?"**

A single awk can filter and aggregate at once — a condition selects lines, a variable accumulates, and the `END` block prints.

```
awk '$7 ~ /^\/api\// && $9 == 200 {s += $10} END {print s}' /var/log/lab/access.log
```

- `$7 ~ /regex/` — does field 7 match the regex? A `/` inside the regex is escaped as `\/`.
- The variable `s` starts at 0 without declaration; the `END` block runs once after all lines are read.

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

- Same command as above, with the output saved to a file via `>`.
