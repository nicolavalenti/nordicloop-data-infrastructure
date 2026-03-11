-- Q1: Total CO2 saved per organisation
-- Business question: which orgs are generating the most environmental value through reuse?
SELECT o.name AS organisation,
    ROUND(SUM(im.co2_saved_kg)::numeric, 1) AS total_co2_saved_kg
FROM organisations o
    LEFT JOIN internal_matches im ON im.org_id = o.id
    AND im.status = 'completed'
GROUP BY o.name
ORDER BY total_co2_saved_kg DESC NULLS LAST;
-- Q2: Match completion rate per organisation
-- Business question: which orgs upload but fail to close internal matches?
SELECT o.name AS organisation,
    COUNT(im.id) AS total_proposed,
    SUM(
        CASE
            WHEN im.status = 'completed' THEN 1
            ELSE 0
        END
    ) AS completed,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN im.status = 'completed' THEN 1
                ELSE 0
            END
        ) / NULLIF(COUNT(im.id), 0),
        1
    ) AS completion_pct
FROM organisations o
    LEFT JOIN internal_matches im ON im.org_id = o.id
GROUP BY o.name
ORDER BY completion_pct DESC NULLS LAST;
-- Q3: LLM override rate by category
-- Business question: which material categories is our AI model least confident on?
SELECT c.name AS category,
    COUNT(*) AS total_classified,
    SUM(
        CASE
            WHEN ac.llm_decision = 'overridden' THEN 1
            ELSE 0
        END
    ) AS overrides,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN ac.llm_decision = 'overridden' THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        1
    ) AS override_pct
FROM ai_classifications ac
    JOIN material_items mi ON mi.id = ac.material_item_id
    JOIN categories c ON c.id = mi.category_id
GROUP BY c.name
ORDER BY override_pct DESC;
-- Q4: Running total of CO2 saved over time
-- Business question: what does our cumulative environmental impact look like month by month?
SELECT DATE_TRUNC('month', im.completed_at) AS month,
    ROUND(SUM(im.co2_saved_kg)::numeric, 1) AS co2_this_month,
    ROUND(
        SUM(SUM(im.co2_saved_kg)) OVER (
            ORDER BY DATE_TRUNC('month', im.completed_at)
        )::numeric,
        1
    ) AS cumulative_co2
FROM internal_matches im
WHERE im.status = 'completed'
    AND im.completed_at IS NOT NULL
GROUP BY DATE_TRUNC('month', im.completed_at)
ORDER BY month;