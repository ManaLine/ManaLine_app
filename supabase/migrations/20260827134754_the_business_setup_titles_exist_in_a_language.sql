-- OW-000's two titles were ManaText('set up new business') and
-- ManaText('first business setup') -- keys with SPACES that are in no
-- translation table. They fell through to the key text, which Title-Cases to
-- something that reads correctly in English and is English in every other
-- language. The same trick was hiding in the live photo capture screen.
--
-- Adding the rows rather than keeping the fallback: a title nobody can read
-- is a title, and this is the first screen a new Owner sees.
insert into ui_translations (translation_key, english, telugu) values
  ('first_business_setup', 'First Business Setup', 'మొదటి వ్యాపార ఏర్పాటు'),
  ('set_up_new_business', 'Set Up New Business', 'కొత్త వ్యాపారాన్ని ఏర్పాటు చేయండి')
on conflict (translation_key) do nothing;
