"""add group3_inpn column in synthese default nomenclature values

Revision ID: 2a305b9cfd15
Revises: f1dd984bff97
Create Date: 2023-08-21 08:04:20.163943

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "2a305b9cfd15"
down_revision = "f1dd984bff97"
branch_labels = None
depends_on = None


def upgrade():
    op.execute(
        "ALTER TABLE gn_synthese.defaults_nomenclatures_value ADD group3_inpn varchar(255) NOT NULL DEFAULT '0'::character varying;"
    )


def downgrade():
    op.execute("ALTER TABLE gn_synthese.defaults_nomenclatures_value DROP group3_inpn")
