-- sqlite3.exe -readonly <今回のdb_path> から実行する。
-- DBパスはdemo.readyログで確認する。古いtemp DBを選ばない。
SELECT 'books' AS entity, count(*) AS n FROM books
UNION ALL SELECT 'library_systems', count(*) FROM library_systems
UNION ALL SELECT 'library_memberships', count(*) FROM library_memberships
UNION ALL SELECT 'loans', count(*) FROM loans
UNION ALL SELECT 'outbox_events', count(*) FROM outbox_events
UNION ALL SELECT 'applied_events', count(*) FROM applied_events
UNION ALL SELECT 'domain_events', count(*) FROM domain_events;

SELECT s.city, l.status, count(l.id) AS n
FROM library_systems s LEFT JOIN loans l ON l.system_id = s.system_id
GROUP BY s.system_id, l.status ORDER BY s.system_id, l.status;

SELECT l.id, b.title, l.system_id, l.status, l.pickup_library_id,
       l.due_on, l.pickup_due_on, l.note
FROM loans l JOIN books b ON b.id = l.book_id
ORDER BY l.system_id, l.status, l.id;

SELECT count(*) AS marker_count FROM loans WHERE note = 'demo-sql-probe-added';
SELECT count(*) AS changed_due_count FROM loans WHERE due_on = '2099-01-01';
PRAGMA integrity_check;
