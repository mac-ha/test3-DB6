CREATE SCHEMA payroll_lab;

CREATE TABLE payroll_lab.employees (
    employee_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,

    basic_salary NUMERIC(12,2) NOT NULL
        CHECK (basic_salary >= 0),

    allowance NUMERIC(12,2) NOT NULL
        CHECK (allowance >= 0),

    deduction NUMERIC(12,2) NOT NULL
        CHECK (deduction >= 0),

    active BOOLEAN NOT NULL
);

CREATE TABLE payroll_lab.payroll (
    payroll_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    employee_id INTEGER NOT NULL,

    pay_month DATE NOT NULL,

    gross_pay NUMERIC(12,2) NOT NULL,
    net_pay NUMERIC(12,2) NOT NULL,

    CONSTRAINT fk_payroll_employee
        FOREIGN KEY (employee_id)
        REFERENCES payroll_lab.employees(employee_id),

    CONSTRAINT uq_employee_month
        UNIQUE(employee_id, pay_month)
);

CREATE TABLE payroll_lab.salary_audit (
    audit_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    employee_id INTEGER NOT NULL,

    old_salary NUMERIC(12,2) NOT NULL,
    new_salary NUMERIC(12,2) NOT NULL,

    changed_at TIMESTAMP NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_audit_employee
        FOREIGN KEY (employee_id)
        REFERENCES payroll_lab.employees(employee_id)
);

--seed employees
INSERT INTO payroll_lab.employees
(full_name, basic_salary, allowance, deduction, active)
VALUES

('John Banda',5000,500,300,TRUE),
('Mary Phiri',6000,700,400,TRUE),
('Peter Zulu',4500,300,200,FALSE);

--seed payroll
INSERT INTO payroll_lab.payroll
(employee_id,pay_month,gross_pay,net_pay)
VALUES

(1,'2026-09-01',5500,5200),
(1,'2026-10-01',5500,5200),

(2,'2026-09-01',6700,6300),
(2,'2026-10-01',6700,6300);

--B--
CREATE OR REPLACE FUNCTION
payroll_lab.fn_net_pay(
    p_employee_id INTEGER
)
RETURNS NUMERIC(12,2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_basic NUMERIC(12,2);
    v_allowance NUMERIC(12,2);
    v_deduction NUMERIC(12,2);

    v_net NUMERIC(12,2);
BEGIN

    SELECT
        basic_salary,
        allowance,
        deduction
    INTO
        v_basic,
        v_allowance,
        v_deduction
    FROM payroll_lab.employees
    WHERE employee_id = p_employee_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
        'Unknown employee';
    END IF;

    v_net :=
        (v_basic + v_allowance)
        - v_deduction;

    IF v_net < 0 THEN
        RAISE EXCEPTION
        'Negative net pay not allowed';
    END IF;

    RETURN v_net;

END;
$$;

--C--
CREATE OR REPLACE PROCEDURE
payroll_lab.pr_process_payroll(
    p_month DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    emp RECORD;
    v_gross NUMERIC(12,2);
    v_net NUMERIC(12,2);
BEGIN

    IF p_month <>
       date_trunc('month', p_month)::date
    THEN
        RAISE EXCEPTION
        'Pay month must be first day of month';
    END IF;

    FOR emp IN

        SELECT *
        FROM payroll_lab.employees
        WHERE active = TRUE

    LOOP

        v_gross :=
            emp.basic_salary
            + emp.allowance;

        v_net :=
            payroll_lab.fn_net_pay(
                emp.employee_id
            );

        IF NOT EXISTS
        (
            SELECT 1
            FROM payroll_lab.payroll
            WHERE employee_id = emp.employee_id
            AND pay_month = p_month
        )
        THEN

            INSERT INTO payroll_lab.payroll
            (
                employee_id,
                pay_month,
                gross_pay,
                net_pay
            )
            VALUES
            (
                emp.employee_id,
                p_month,
                v_gross,
                v_net
            );

        END IF;

    END LOOP;

END;
$$;

--D--

CREATE OR REPLACE FUNCTION
payroll_lab.fn_salary_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.basic_salary <>
       NEW.basic_salary
    THEN

        INSERT INTO payroll_lab.salary_audit
        (
            employee_id,
            old_salary,
            new_salary,
            changed_at
        )
        VALUES
        (
            NEW.employee_id,
            OLD.basic_salary,
            NEW.basic_salary,
            CURRENT_TIMESTAMP
        );

    END IF;

    RETURN NEW;

END;
$$;

--trigger--
CREATE TRIGGER trg_salary_audit
AFTER UPDATE
ON payroll_lab.employees
FOR EACH ROW
EXECUTE FUNCTION
payroll_lab.fn_salary_audit();

--E--

CREATE OR REPLACE VIEW
payroll_lab.v_payroll_report AS
SELECT
    e.full_name,
    p.pay_month,
    p.gross_pay,
    p.net_pay
FROM payroll_lab.payroll p
JOIN payroll_lab.employees e
ON p.employee_id = e.employee_id;

--F--

CREATE INDEX idx_payroll_month
ON payroll_lab.payroll(pay_month);

EXPLAIN

SELECT *
FROM payroll_lab.payroll
WHERE pay_month = DATE '2026-11-01';

--G--

CALL payroll_lab.pr_process_payroll(
    date_trunc(
        'month',
        CURRENT_DATE - INTERVAL '1 month'
    )::date
);