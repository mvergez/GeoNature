"""Create public functions

Revision ID: 081ddfc0abb4
Revises: 
Create Date: 2020-12-31 17:18:30.125489

"""
from alembic import op, context
import sqlalchemy as sa
from sqlalchemy.sql import text
import pkg_resources


# revision identifiers, used by Alembic.
revision = '081ddfc0abb4'
down_revision = None
branch_labels = ('geonature',)
depends_on = None


def upgrade():
    operations = pkg_resources.resource_string("geonature.migrations", "data/public.sql").decode('utf-8')
    op.execute(operations)


def downgrade():
    op.execute('DROP FUNCTION public.fct_trg_meta_dates_change')
