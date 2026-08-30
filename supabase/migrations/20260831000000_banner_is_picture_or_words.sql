-- A banner is a picture, or it is words. Never both.
--
-- `imageWithText` drew the headline over a scrim on top of the artwork, and it is the
-- one mode nobody can design for: the merchant's photograph decides where the dark parts
-- are, and the title lands wherever it lands. On a picture of grilled meat at dusk the
-- white text disappears into it, and there is no setting on either screen that fixes it
-- because the fix depends on the picture.
--
-- So the two modes that are actually designable stay. A picture that fills its own frame
-- and says whatever the merchant had printed on it, or words on a colour that was chosen
-- for them to sit on.
update promotions set render_mode = 'image' where render_mode = 'imageWithText';

alter table promotions drop constraint promotions_render_mode_check;
alter table promotions add constraint promotions_render_mode_check
  check (render_mode in ('text', 'image'));

-- The colour behind the words.
--
-- Stored as a hex string rather than a token name because the palette is a product
-- decision that will move — a token list in the schema is a migration every time somebody
-- wants a different green — and the constraint is what stops it being a free-text field
-- that eventually holds "أحمر".
--
-- Null means the brand gradient, which is what every text banner drew before this column
-- existed and what a merchant who does not care should still get.
alter table promotions add column background_color text
  check (background_color is null or background_color ~ '^#[0-9A-Fa-f]{6}$');

comment on column promotions.background_color is
  'Hex ground for a text banner. Null is the brand gradient. The text colour is not '
  'stored: it is computed from this one''s luminance, so a pale ground can never be '
  'saved with pale text on it.';
