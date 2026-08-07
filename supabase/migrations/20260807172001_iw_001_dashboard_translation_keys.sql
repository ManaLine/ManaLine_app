INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('total_investment_balance', 'Total Investment Balance', 'మొత్తం పెట్టుబడి నిల్వ'),
('active_investments', 'Active Investments', 'యాక్టివ్ పెట్టుబడులు'),
('interest_accrued', 'Interest Accrued', 'పోగుపడిన వడ్డీ'),
('interest_paid_to_date', 'Interest Paid to Date', 'ఇప్పటివరకు చెల్లించిన వడ్డీ'),
('pending_withdrawal_requests', 'Pending Withdrawal Requests', 'పెండింగ్ ఉపసంహరణ అభ్యర్థనలు'),
('pending_interest_payment_requests', 'Pending Interest Payment Requests', 'పెండింగ్ వడ్డీ చెల్లింపు అభ్యర్థనలు'),
('find_investor_membership_note', 'Find a Business to request Investor membership. Once the Owner approves, it will appear here.', 'ఇన్వెస్టర్ సభ్యత్వం కోసం అభ్యర్థించడానికి ఒక వ్యాపారాన్ని కనుగొనండి. యజమాని ఆమోదించిన తర్వాత, అది ఇక్కడ కనిపిస్తుంది.')
ON CONFLICT (translation_key) DO NOTHING;
