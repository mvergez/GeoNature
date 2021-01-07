"""Declare geonature in utilisateurs schema

Revision ID: 1b6d2229b2dd
Revises: 
Create Date: 2020-12-31 11:07:58.325980

"""
from alembic import op, context
import sqlalchemy as sa
from sqlalchemy.sql import text
import pkg_resources


# revision identifiers, used by Alembic.
revision = '1b6d2229b2dd'
down_revision = '081ddfc0abb4'
branch_labels = []
depends_on = None


def upgrade():
    operations = pkg_resources.resource_string("geonature.migrations", "data/adds_for_usershub.sql").decode('utf-8')
    op.execute(operations)


def downgrade():
    op.execute("DELETE FROM utilisateurs.cor_role_app_profil WHERE id_application IN (SELECT id_application FROM utilisateurs.t_applications WHERE code_application = 'GN')")
    op.execute("DELETE FROM utilisateurs.cor_profil_for_app WHERE id_application IN (SELECT id_application FROM utilisateurs.t_applications WHERE code_application = 'GN')")
    op.execute("DELETE FROM utilisateurs.t_applications WHERE code_application = 'GN'")
