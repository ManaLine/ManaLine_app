-- An Agent can ask for BF, and be answered.
--
-- The Agent's side of this already existed as a dead end: issuing a loan with
-- no float raised "Insufficient agent BF", and that was the whole of it. The
-- Agent is standing in a village with a customer in front of them; there was
-- nothing they could DO with that sentence. The only route was a phone call
-- the app knew nothing about, and the Owner had no record that anyone had
-- asked.
--
-- So the refusal becomes a conversation: the Agent names an amount, the Owner
-- sees who asked and for how much, and answers -- approving (at the asked
-- figure or a different one, because the Owner knows what is in the till) or
-- rejecting. Either answer reaches the Agent, because being refused and being
-- ignored look identical from the road and only one of them was meant.
--
-- status is text with a CHECK rather than an enum: three values that belong to
-- this table alone, and an enum would be a type migration to add a fourth.
CREATE TABLE IF NOT EXISTS agent_bf_requests (
  request_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id          uuid NOT NULL REFERENCES businesses(business_id),
  membership_id        uuid NOT NULL REFERENCES business_members(membership_id),
  requested_amount     numeric(14,0) NOT NULL CHECK (requested_amount > 0),
  reason               text,
  business_date        date NOT NULL DEFAULT CURRENT_DATE,
  status               text NOT NULL DEFAULT 'Pending'
                         CHECK (status IN ('Pending','Approved','Rejected')),
  decided_amount       numeric(14,0),
  decided_by_person_id bigint REFERENCES persons(person_id),
  decided_at           timestamp,
  decision_note        text,
  created_at           timestamp NOT NULL DEFAULT now(),

  -- An answered request must say when it was answered, and an approved one
  -- must say how much was actually granted. Without these a row could claim
  -- 'Approved' while carrying no figure, and the Agent's history would show a
  -- yes that moved no money.
  CONSTRAINT chk_bf_request_decided
    CHECK (status = 'Pending' OR decided_at IS NOT NULL),
  CONSTRAINT chk_bf_request_approved_amount
    CHECK (status <> 'Approved' OR (decided_amount IS NOT NULL AND decided_amount > 0))
);

COMMENT ON TABLE agent_bf_requests IS
  'An Agent asking the Owner for BF float, and the Owner''s answer. One '
  'Pending row per agent at a time; a second ask raises the amount on the '
  'open one rather than queueing a duplicate.';

-- One open ask per Agent. A second request is the same conversation continuing,
-- not a new one, and a queue of them would make the Owner answer the same
-- question three times.
CREATE UNIQUE INDEX IF NOT EXISTS uq_bf_request_one_pending_per_agent
  ON agent_bf_requests (membership_id) WHERE status = 'Pending';

-- The Owner's screen asks one question -- what is waiting for me -- so the
-- index answers only that, rather than carrying every decided row forever.
CREATE INDEX IF NOT EXISTS ix_bf_requests_business_pending
  ON agent_bf_requests (business_id) WHERE status = 'Pending';

ALTER TABLE agent_bf_requests ENABLE ROW LEVEL SECURITY;

-- The Owner sees and answers every request in their book.
DROP POLICY IF EXISTS bf_requests_owner_all ON agent_bf_requests;
CREATE POLICY bf_requests_owner_all ON agent_bf_requests
  FOR ALL USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

-- The Agent sees their OWN requests -- what they asked, and what came back.
-- Read only: the amount is written through request_agent_bf, which is what
-- notifies the Owner. A direct insert would create a request nobody hears.
DROP POLICY IF EXISTS bf_requests_agent_own ON agent_bf_requests;
CREATE POLICY bf_requests_agent_own ON agent_bf_requests
  FOR SELECT USING (app.membership_belongs_to_current_person(membership_id));

GRANT SELECT ON agent_bf_requests TO authenticated;
GRANT ALL ON agent_bf_requests TO service_role;
