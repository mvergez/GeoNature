"""Create geonature schemas

Revision ID: 89c783c08785
Revises: 
Create Date: 2020-12-31 11:07:58.325980

"""
from alembic import op, context
import sqlalchemy as sa
from sqlalchemy.sql import text
import pkg_resources
from distutils.util import strtobool


# revision identifiers, used by Alembic.
revision = '89c783c08785'
down_revision = '1b6d2229b2dd'
branch_labels = []
depends_on = (
    '6ddded935869',  # ref_nomenclatures (& taxonomie & utilisateurs)
    '7d4235aa8483',  # ref_habitats
)


def upgrade():
    try:
        local_srid = context.get_x_argument(as_dictionary=True)['local-srid']
    except KeyError:
        raise Exception("Missing local srid, please use -x local-srid=...")
    sql_files = [
        'gn_commons.sql',
        'gn_meta.sql',
        'ref_geo.sql',
        'gn_imports.sql',
        'gn_synthese.sql',
        'gn_synthese_default_values.sql',
        'gn_commons_synthese.sql',
        'gn_exports.sql',
        'gn_monitoring.sql',
        'gn_permissions.sql',
        'gn_permissions_data.sql',
        'gn_sensitivity.sql',
    ]
    if strtobool(context.get_x_argument(as_dictionary=True).get('meta-sample', 'false')):
        sql_files += ['gn_meta_data.sql']
    for sql_file in sql_files:
        operations = pkg_resources.resource_string("geonature.migrations", f"data/{sql_file}").decode('utf-8')
        op.get_bind().execute(text(operations), MYLOCALSRID=local_srid)


def downgrade():
    op.execute('DROP SCHEMA gn_commons CASCADE')
    op.execute('DROP SCHEMA gn_meta CASCADE')
    op.execute('DROP SCHEMA ref_geo CASCADE')
    op.execute('DROP SCHEMA gn_imports CASCADE')
    op.execute('DROP SCHEMA gn_synthese CASCADE')
    op.execute('DROP SCHEMA gn_exports CASCADE')
    op.execute('DROP SCHEMA gn_monitoring CASCADE')
    op.execute('DROP SCHEMA gn_permissions CASCADE')
    op.execute('DROP SCHEMA gn_sensitivity CASCADE')
