-- "Collection Mode" and "Customer Management" are what a spec calls a screen.
-- The footer already calls them Collections and Customers, and reading one
-- name on the tab and another at the top of the screen it opens is a small,
-- constant friction for somebody working fast.
--
-- Changed at the key, not at each call site: both names are used in a dozen
-- places, and a rename per screen is how two of them keep the old word.
UPDATE ui_translations
   SET english = 'Collections', telugu = 'వసూళ్లు'
 WHERE translation_key = 'collection_mode';

UPDATE ui_translations
   SET english = 'Customers', telugu = 'కస్టమర్లు'
 WHERE translation_key = 'customer_management';
