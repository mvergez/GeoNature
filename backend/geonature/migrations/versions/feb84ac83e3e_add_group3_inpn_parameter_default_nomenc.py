"""add group3_inpn parameter in synthese get_default_nomenclature_value

Revision ID: feb84ac83e3e
Revises: 2a305b9cfd15
Create Date: 2023-08-21 08:22:10.352738

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "feb84ac83e3e"
down_revision = "2a305b9cfd15"
branch_labels = None
depends_on = None


def upgrade():
    # To keep compatibility with the old get_default_nomenclature_value, a new one is created here
    op.execute(
        """
        CREATE OR REPLACE FUNCTION gn_synthese.get_default_nomenclature_value(myidtype character varying, myidorganism integer DEFAULT NULL::integer, myregne character varying DEFAULT '0'::character varying, mygroup2inpn character varying DEFAULT '0'::character VARYING, mygroup3inpn character varying DEFAULT '0'::character varying)
        RETURNS integer
        LANGUAGE plpgsql
        IMMUTABLE
        AS $function$
            --Function that returns the default nomenclature id with wanted nomenclature type, organism id, regne, group2_inpn, group3_inpn
            --Return -1 if nothing matches with given parameters
            DECLARE
                thenomenclatureid integer;
            BEGIN
                SELECT INTO thenomenclatureid id_nomenclature FROM (
                    SELECT
                        id_nomenclature,
                        regne,
                        group2_inpn,
                        group3_inpn,
                        CASE
                            WHEN n.id_organism = myidorganism THEN 1
                            ELSE 0
                        END prio_organisme
                    FROM gn_synthese.defaults_nomenclatures_value n
                    JOIN utilisateurs.bib_organismes o
                    ON o.id_organisme = n.id_organism
                    WHERE mnemonique_type = myidtype
                    AND (n.id_organism = myidorganism OR n.id_organism = NULL OR o.nom_organisme = 'ALL')
                    AND (regne = myregne OR regne = '0')
                    AND (group2_inpn = mygroup2inpn OR group2_inpn = '0')
                    AND (group3_inpn = mygroup3inpn OR group3_inpn = '0')
                ) AS defaults_nomenclatures_value
                ORDER BY group2_inpn DESC, regne DESC, prio_organisme DESC LIMIT 1;
                RETURN thenomenclatureid;
            END;
            $function$
        ;
    """
    )


def downgrade():
    op.execute(
        "DROP FUNCTION gn_synthese.get_default_nomenclature_value(character varying, myidorganism integer, character varying, character varying, character varying);"
    )
