-- Keys for the shared Notifications inbox (lib/shared/notifications_screen.dart).
--
-- The two actionable sections are worded so the verb matches the direction:
-- "Needs Your Approval" is about letting someone into a business you own,
-- "Invitations to You" is about joining someone else's. Approve/Reject versus
-- Accept/Decline is the same distinction carried into the buttons.
--
-- {role} and {business} are substituted client-side and must survive
-- translation intact.
INSERT INTO ui_translations (translation_key, english, telugu, hindi, tamil, kannada) VALUES
  ('needs_your_approval', 'Needs Your Approval', 'మీ ఆమోదం కావాలి', 'आपकी मंज़ूरी चाहिए', 'உங்கள் ஒப்புதல் தேவை', 'ನಿಮ್ಮ ಅನುಮೋದನೆ ಬೇಕು'),
  ('invitations_to_you', 'Invitations to You', 'మీకు ఆహ్వానాలు', 'आपके लिए निमंत्रण', 'உங்களுக்கான அழைப்புகள்', 'ನಿಮಗೆ ಆಹ್ವಾನಗಳು'),
  ('earlier', 'Earlier', 'ఇంతకుముందు', 'पहले', 'முந்தையவை', 'ಹಿಂದಿನವು'),
  ('nothing_waiting_note', 'Nothing is waiting on you.', 'మీ కోసం ఏమీ వేచి లేదు.', 'आपके लिए कुछ भी लंबित नहीं है।', 'உங்களுக்காக எதுவும் காத்திருக்கவில்லை.', 'ನಿಮಗಾಗಿ ಏನೂ ಕಾಯುತ್ತಿಲ್ಲ.'),
  ('could_not_load_notifications', 'Could Not Load Notifications', 'నోటిఫికేషన్లను లోడ్ చేయలేకపోయాం', 'सूचनाएँ लोड नहीं हो सकीं', 'அறிவிப்புகளை ஏற்ற முடியவில்லை', 'ಅಧಿಸೂಚನೆಗಳನ್ನು ಲೋಡ್ ಮಾಡಲಾಗಲಿಲ್ಲ'),
  ('wants_to_join_as_note', 'Wants to join {business} as {role}', '{business}లో {role}గా చేరాలనుకుంటున్నారు', '{business} में {role} के रूप में जुड़ना चाहते हैं', '{business} இல் {role} ஆக சேர விரும்புகிறார்', '{business} ಸೇರಲು ಬಯಸುತ್ತಾರೆ, {role} ಆಗಿ'),
  ('invited_you_as_note', 'Invited you to join as {role}', '{role}గా చేరమని మిమ్మల్ని ఆహ్వానించారు', '{role} के रूप में जुड़ने का निमंत्रण', '{role} ஆக சேர உங்களை அழைத்துள்ளனர்', '{role} ಆಗಿ ಸೇರಲು ನಿಮ್ಮನ್ನು ಆಹ್ವಾನಿಸಿದ್ದಾರೆ'),
  ('proposed_investment', 'Proposed Investment', 'ప్రతిపాదిత పెట్టుబడి', 'प्रस्तावित निवेश', 'முன்மொழியப்பட்ட முதலீடு', 'ಪ್ರಸ್ತಾವಿತ ಹೂಡಿಕೆ'),
  ('decline', 'Decline', 'తిరస్కరించండి', 'अस्वीकार करें', 'நிராகரிக்கவும்', 'ನಿರಾಕರಿಸಿ')
ON CONFLICT (translation_key) DO UPDATE SET
  english = EXCLUDED.english, telugu = EXCLUDED.telugu,
  hindi = EXCLUDED.hindi, tamil = EXCLUDED.tamil, kannada = EXCLUDED.kannada;
