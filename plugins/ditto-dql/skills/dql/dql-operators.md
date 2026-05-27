# DQL Operators and Expressions - Complete Reference

**Read this file ONLY when:** You need complete operator/function syntax beyond the common operators in SKILL.md.

**For basic queries:** Use SKILL.md Common Operators section instead.

---

## Arithmetic Operators

### Binary Operators
```sql
SELECT price + tax AS total FROM orders
SELECT quantity * unit_price AS subtotal FROM line_items
SELECT total / count AS average FROM summaries
SELECT value % 10 AS remainder FROM numbers
SELECT final_price - discount AS net_price FROM products
```

### Unary Operator
```sql
-- Negative values
WHERE balance = -42
WHERE adjustment = -100.50
```

### Functions
```sql
-- Absolute value
SELECT abs(-42) AS positive
SELECT abs(balance) FROM accounts

-- Ceiling (round up)
SELECT ceil(3.7) AS rounded_up    -- Returns 4
SELECT ceil(price) FROM products

-- Floor (round down)
SELECT floor(3.7) AS rounded_down  -- Returns 3
SELECT floor(temperature) FROM sensors
```

---

## String Operations

### Concatenation
```sql
-- Operator: ||
SELECT first_name || ' ' || last_name AS full_name FROM users
SELECT street || ', ' || city || ', ' || state AS address FROM locations

-- Function: concat()
SELECT concat(first_name, ' ', last_name) AS full_name FROM users
SELECT concat(city, ', ', state, ' ', zip) AS location FROM addresses
```

### Pattern Matching Functions
```sql
-- Contains substring
WHERE contains(title, 'urgent')
WHERE contains(description, 'error')
WHERE contains(email, '@example.com')

-- Starts with
WHERE starts_with(email, 'admin')
WHERE starts_with(filename, 'log_')
WHERE starts_with(path, '/home/')

-- Ends with
WHERE ends_with(filename, '.pdf')
WHERE ends_with(email, '@company.com')
WHERE ends_with(url, '.html')
```

### Wildcard Pattern Matching
```sql
-- LIKE (case-sensitive)
WHERE name LIKE 'John%'          -- Starts with 'John'
WHERE name LIKE '%Smith'         -- Ends with 'Smith'
WHERE name LIKE '%middle%'       -- Contains 'middle'
WHERE code LIKE 'AB_123'         -- _ matches single character

-- ILIKE (case-insensitive)
WHERE name ILIKE 'john%'         -- Matches 'John', 'JOHN', 'john'
WHERE email ILIKE '%@gmail.com'
WHERE title ILIKE '%important%'
```

### Regular Expression
```sql
-- regexp_like()
WHERE regexp_like(email, '^[a-z]+@')
WHERE regexp_like(phone, '^\d{3}-\d{3}-\d{4}$')
WHERE regexp_like(zip_code, '^\d{5}(-\d{4})?$')
```

### Length Functions
```sql
-- Byte length
SELECT byte_length(data) FROM documents
SELECT byte_length(binary_content) FROM files

-- Character length
SELECT char_length(text) FROM articles
SELECT char_length(name) FROM users
WHERE char_length(password) >= 8
```

---

## Comparison Operators

### Basic Comparisons
```sql
-- Equality (= or ==)
WHERE status = 'active'
WHERE status == 'active'  -- Same as above

-- Inequality (!= or <>)
WHERE status != 'deleted'
WHERE status <> 'deleted'  -- Same as above

-- Less than
WHERE price < 100
WHERE age < 18

-- Less than or equal
WHERE price <= 99.99
WHERE age <= 65

-- Greater than
WHERE priority > 5
WHERE score > 90

-- Greater than or equal
WHERE priority >= 3
WHERE age >= 18
```

### NULL Behavior
**⚠️ CRITICAL: NULL compared with anything returns NULL (not false)**

```sql
-- ❌ WRONG - Returns NULL, not boolean
WHERE field = NULL
WHERE field != NULL

-- ✅ CORRECT - Use IS NULL / IS NOT NULL
WHERE field IS NULL
WHERE field IS NOT NULL
```

---

## Logical Operators

### AND Operator
```sql
WHERE active AND verified
WHERE price > 10 AND price < 100
WHERE status = 'active' AND role = 'admin'
```

### OR Operator
```sql
WHERE priority = 'high' OR priority = 'urgent'
WHERE status = 'pending' OR status = 'processing'
WHERE age < 18 OR age > 65
```

### NOT Operator
```sql
WHERE NOT deleted
WHERE NOT (status = 'archived' OR status = 'deleted')
WHERE NOT contains(email, 'spam')
```

### Truth Tables
Handles NULL and MISSING values systematically (see official docs for complete tables).

---

## NULL and MISSING Tests

### IS NULL / IS NOT NULL
```sql
-- Field exists with NULL value
WHERE field IS NULL
WHERE optional_value IS NULL

-- Field exists with non-NULL value
WHERE field IS NOT NULL
WHERE required_value IS NOT NULL
```

### IS MISSING / IS NOT MISSING
```sql
-- Field doesn't exist in document
WHERE field IS MISSING
WHERE optional_field IS MISSING

-- Field exists (regardless of value)
WHERE field IS NOT MISSING
WHERE required_field IS NOT MISSING
```

### IS UNKNOWN / IS NOT UNKNOWN
```sql
-- Field is NULL or MISSING
WHERE field IS UNKNOWN
WHERE optional_data IS UNKNOWN

-- Field exists with non-NULL value
WHERE field IS NOT UNKNOWN
WHERE data IS NOT UNKNOWN
```

**Difference Summary:**
- `IS NULL` - Field exists, value is NULL
- `IS MISSING` - Field doesn't exist
- `IS UNKNOWN` - Field is NULL OR doesn't exist

---

## Conditional Logic

### coalesce() - First Non-NULL Value
```sql
-- Returns first non-null argument
SELECT coalesce(nickname, first_name, 'Unknown') AS display_name FROM users
SELECT coalesce(mobile, home_phone, work_phone) AS contact FROM contacts
SELECT coalesce(discount_price, regular_price) AS final_price FROM products

-- Use in WHERE
WHERE coalesce(override_status, default_status) = 'active'
```

### decode() - Case-When Equivalent
```sql
-- decode(expression, match1, result1, match2, result2, ..., default)
SELECT decode(status,
  'active', 'Active User',
  'inactive', 'Inactive User',
  'pending', 'Pending Approval',
  'Unknown Status'
) AS status_display FROM users

SELECT decode(priority,
  1, 'Urgent',
  2, 'High',
  3, 'Normal',
  4, 'Low',
  'No Priority'
) AS priority_label FROM tasks
```

### nvl() - NULL Replacement
```sql
-- nvl(expression, default_value)
SELECT nvl(optional_field, 'default') AS field FROM data
SELECT nvl(discount, 0) AS discount_amount FROM products
WHERE nvl(enabled, false) = true
```

---

## Collection Membership

### IN Operator
```sql
-- Single value list
WHERE status IN ('active', 'pending', 'approved')
WHERE priority IN (1, 2, 3)
WHERE category IN ('urgent', 'important')

-- With subquery results (when available)
WHERE user_id IN ('user-1', 'user-2', 'user-3')
```

### NOT IN Operator
```sql
WHERE status NOT IN ('archived', 'deleted')
WHERE priority NOT IN (0, 4, 5)
WHERE category NOT IN ('spam', 'junk')
```

---

## Array Operations

### array_contains()
```sql
-- Check if array contains value
WHERE array_contains(tags, 'important')
WHERE array_contains(categories, 'electronics')
WHERE array_contains(roles, 'admin')
```

### array_contains_null()
```sql
-- Check if array contains NULL
WHERE array_contains_null(optional_fields)
WHERE array_contains_null(nullable_values)
```

### array_length()
```sql
-- Get array length
SELECT array_length(items) AS item_count FROM lists
SELECT array_length(tags) AS tag_count FROM articles
WHERE array_length(permissions) > 0
WHERE array_length(tags) >= 3
```

**Note:** Array and object literals supported in SDK 4.8+

---

## Object Operations

### object_length()
```sql
-- Count key-value pairs
SELECT object_length(metadata) AS field_count FROM documents
SELECT object_length(settings) AS setting_count FROM config
WHERE object_length(data) > 0
```

### object_keys()
```sql
-- Extract top-level keys as array
SELECT object_keys(settings) AS keys FROM config
SELECT object_keys(metadata) AS fields FROM documents
```

### object_values()
```sql
-- Extract top-level values as array
SELECT object_values(config) AS values FROM settings
SELECT object_values(metadata) AS field_values FROM documents
```

---

## Type Testing

### Type Check Functions
```sql
-- is_boolean()
WHERE is_boolean(field)
WHERE is_boolean(enabled)

-- is_number()
WHERE is_number(value)
WHERE is_number(price)

-- is_string()
WHERE is_string(name)
WHERE is_string(description)
```

### type() Function
```sql
-- Returns type as string
SELECT type(field) AS field_type FROM data
SELECT type(value) AS value_type FROM mixed_data

-- Use in WHERE
WHERE type(field) = 'string'
WHERE type(value) = 'number'
```

**Type Names:**
- `'boolean'`
- `'number'`
- `'string'`
- `'array'`
- `'object'`
- `'null'`

---

## Date/Time Functions

### date_cast() - Convert to Epoch Milliseconds
```sql
-- Convert ISO-8601 string to epoch ms
SELECT date_cast('2024-12-22') AS timestamp
SELECT date_cast('2024-12-22T15:30:00Z') AS datetime_ms

-- Use in WHERE
WHERE created_at > date_cast('2024-01-01')
WHERE updated_at >= date_cast('2024-12-01T00:00:00Z')
```

### date_format() - Format with Timezone
```sql
-- date_format(timestamp, timezone)
SELECT date_format(timestamp, 'America/New_York') AS ny_time FROM events
SELECT date_format(created_at, 'Europe/London') AS uk_time FROM logs
SELECT date_format(clock(), 'America/Los_Angeles') AS current_time
```

### date_add() - Add Time Interval
```sql
-- date_add(timestamp, amount, unit)
-- Units: 'years', 'months', 'days', 'hours', 'minutes', 'seconds', 'milliseconds'

SELECT date_add(created_at, 7, 'days') AS due_date FROM tasks
SELECT date_add(purchased_at, 1, 'years') AS warranty_expires FROM products
SELECT date_add(clock(), 30, 'minutes') AS expires_at

-- Use in WHERE
WHERE date_add(created_at, 30, 'days') < clock()
WHERE expires_at > date_add(clock(), 1, 'hours')
```

### date_sub() - Subtract Time Interval
```sql
-- date_sub(timestamp, amount, unit)
SELECT date_sub(expires_at, 1, 'month') AS reminder_date FROM subscriptions
SELECT date_sub(deadline, 7, 'days') AS warning_date FROM projects
SELECT date_sub(clock(), 1, 'hours') AS one_hour_ago

-- Use in WHERE
WHERE created_at >= date_sub(clock(), 24, 'hours')
WHERE updated_at > date_sub(clock(), 7, 'days')
```

### date_diff() - Calculate Interval
```sql
-- date_diff(end, start, unit)
-- Returns difference in specified unit

SELECT date_diff(end_date, start_date, 'days') AS duration FROM projects
SELECT date_diff(clock(), created_at, 'hours') AS age_hours FROM tasks
SELECT date_diff(deadline, clock(), 'minutes') AS minutes_remaining FROM events

-- Use in WHERE
WHERE date_diff(clock(), created_at, 'days') > 30
WHERE date_diff(expires_at, clock(), 'hours') < 24
```

### clock() - Current Execution Time
```sql
-- Returns current time as epoch milliseconds
SELECT clock() AS current_time
SELECT clock() - created_at AS age_ms FROM documents

-- Use in INSERT
INSERT INTO events DOCUMENTS ({
  '_id': :id,
  'timestamp': clock(),
  'event': 'login'
})

-- Use in UPDATE
UPDATE documents SET updated_at = clock() WHERE _id = :id

-- Use in WHERE
WHERE created_at <= clock()
WHERE expires_at > clock()
```

### tz_offset() - Timezone Offset
```sql
-- Returns timezone offset in seconds
SELECT tz_offset('America/Los_Angeles') AS offset
SELECT tz_offset('Europe/London') AS uk_offset
SELECT tz_offset('Asia/Tokyo') AS japan_offset
```

---

## Aggregate Functions

### COUNT()
```sql
-- Count all rows
SELECT COUNT(*) AS total FROM tasks

-- Count non-null values
SELECT COUNT(assignee) AS assigned_count FROM tasks

-- Count distinct values
SELECT COUNT(DISTINCT category) AS category_count FROM products
SELECT COUNT(DISTINCT assignee) AS assignee_count FROM tasks
```

### SUM()
```sql
-- Sum values
SELECT SUM(price) AS total_revenue FROM orders
SELECT SUM(quantity) AS total_items FROM line_items

-- Sum distinct (rare use case)
SELECT SUM(DISTINCT amount) FROM payments
```

### AVG()
```sql
-- Average value
SELECT AVG(price) AS avg_price FROM products
SELECT AVG(rating) AS avg_rating FROM reviews
SELECT AVG(age) AS avg_age FROM users
```

### MIN() and MAX()
```sql
-- Minimum value
SELECT MIN(price) AS lowest_price FROM products
SELECT MIN(created_at) AS first_entry FROM logs

-- Maximum value
SELECT MAX(price) AS highest_price FROM products
SELECT MAX(updated_at) AS last_modified FROM documents
```

**⚠️ Aggregate "Dam" Behavior:**
Aggregate functions process ALL documents before returning results (non-streaming).

---

## Special Considerations

### CASE Expressions
DQL does not have CASE WHEN syntax. Use `decode()` function instead:

```sql
-- ❌ NOT SUPPORTED
SELECT CASE
  WHEN status = 'active' THEN 'Active'
  WHEN status = 'inactive' THEN 'Inactive'
  ELSE 'Unknown'
END FROM users

-- ✅ USE decode() INSTEAD
SELECT decode(status,
  'active', 'Active',
  'inactive', 'Inactive',
  'Unknown'
) AS status_label FROM users
```

### ORDER BY Type Hierarchy

Sort order by type (ascending):
boolean → number → binary → string → array → object → null → missing

```sql
-- Mixed types sort in this order
SELECT * FROM mixed_data ORDER BY value ASC
-- Results: true, 42, "text", [1,2,3], {}, null, missing
```

### DISTINCT Memory Usage

⚠️ DISTINCT buffers all results in memory (performance impact on large datasets).

```sql
-- ⚠️ Buffers all in memory
SELECT DISTINCT category FROM products

-- ✅ Better: Use GROUP BY
SELECT category FROM products GROUP BY category

-- ❌ Never use with _id (already unique)
SELECT DISTINCT _id FROM tasks
```

---

## Operator Precedence

From highest to lowest:
1. Unary `-` (negation)
2. `*`, `/`, `%` (multiplication, division, modulo)
3. `+`, `-` (addition, subtraction)
4. `||` (concatenation)
5. Comparison operators (`=`, `!=`, `<`, `>`, `<=`, `>=`)
6. `NOT`
7. `AND`
8. `OR`

**Use parentheses for clarity:**
```sql
WHERE (status = 'active' AND verified = true) OR admin = true
WHERE price * quantity > 100 AND (discount IS NULL OR discount < 0.1)
```

---

## Performance Tips

1. **Use specific comparisons over functions when possible**
   ```sql
   -- ✅ Better (can use index)
   WHERE created_at >= '2024-01-01'

   -- ❌ Slower (function prevents index use)
   WHERE date_format(created_at, 'UTC') >= '2024-01-01'
   ```

2. **Avoid DISTINCT on large result sets** - Buffers all in memory

3. **Use IN for multiple values** - More efficient than multiple OR
   ```sql
   -- ✅ Better
   WHERE status IN ('active', 'pending', 'approved')

   -- ❌ Slower
   WHERE status = 'active' OR status = 'pending' OR status = 'approved'
   ```

4. **Push filters into WHERE** - Don't filter in HAVING if possible
   ```sql
   -- ✅ Better (filters before aggregation)
   SELECT category, COUNT(*) FROM products
   WHERE NOT deleted
   GROUP BY category

   -- ❌ Slower (aggregates all, then filters)
   SELECT category, COUNT(*) FROM products
   GROUP BY category
   HAVING category != 'deleted'
   ```

---

## Common Mistakes

### String Literal Quotes
```sql
-- ❌ WRONG - Double quotes NOT supported
WHERE color = "blue"

-- ✅ CORRECT - Single quotes only
WHERE color = 'blue'
```

### NULL Comparisons
```sql
-- ❌ WRONG - Returns NULL, not boolean
WHERE field = NULL

-- ✅ CORRECT
WHERE field IS NULL
```

### Missing Field Checks
```sql
-- ❌ WRONG - May not work as expected
WHERE optional_field = NULL

-- ✅ CORRECT - Check if field doesn't exist
WHERE optional_field IS MISSING

-- ✅ OR - Check both NULL and MISSING
WHERE optional_field IS UNKNOWN
```

---

## Official Documentation

- **Operator Expressions:** https://docs.ditto.live/dql/operator-expressions
- **DQL Overview:** https://docs.ditto.live/dql/dql
