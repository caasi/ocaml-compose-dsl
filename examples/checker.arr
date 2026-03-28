-- checker.arr — structural well-formedness validation
--
-- Ensures every `?` has a matching `|||`.
-- Warns about misuse like `a? ||| b`.

-- Core transforms
normalize :: Expr -> Expr;            -- strip Group wrappers (graph reduction)
scan_questions :: Expr -> Int;        -- tally: +1 per `?`, −1 per `|||`
tail_has_question :: Expr -> Bool;    -- `?` in tail position?

-- Balance check: normalize, scan, warn if unmatched
normalize >>> scan_questions >>> warn_if_unmatched :: Int -> ();

-- Alt: detect `?` as `|||` operand, adjust balance per side
(normalize &&& normalize)
  >>> (tail_has_question *** tail_has_question)
  >>> warn_if_misused
  >>> (check_balance_adj *** check_balance_adj);

-- Walk dispatches by node type:
--   Seq(a, b)     → walk(a) >>> walk(b)
--   Par/Fanout    → balance each, walk each
--   Alt(a, b)     → check_alt(a, b), walk each
--   Loop(body)    → balance(body), walk(body)
--   App(fn, args) → balance each positional arg

-- Full check: balance + walk, mapped over all statements
let check = check_balance >>> walk :: Expr -> Result in
map(check) :: Program -> Result
