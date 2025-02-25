import { Component, OnInit, Input, OnDestroy, Output, EventEmitter  } from "@angular/core";
import { FormGroup, FormArray } from "@angular/forms";
import { Subscription } from "rxjs";

import { OcctaxFormService } from "../occtax-form.service";
import { ModuleConfig } from "../../module.config";
import { AppConfig } from "@geonature_config/app.config";
import { OcctaxFormOccurrenceService } from "../occurrence/occurrence.service";
import { OcctaxFormCountingService } from "./counting.service";
import { OcctaxFormCountingsService } from "./countings.service";

@Component({
  selector: "pnx-occtax-form-counting",
  templateUrl: "./counting.component.html",
  styleUrls: ["./counting.component.scss"],
  providers: [OcctaxFormCountingService]
})
export class OcctaxFormCountingComponent implements OnInit, OnDestroy {

  public occtaxConfig = ModuleConfig;
  public appConfig = AppConfig;
  public data : any;

  @Input('value') 
  set counting(value: any) { this.occtaxFormCountingService.counting.next(value); };
  public sub: Subscription
  @Output() lifeStageChange = new EventEmitter();

  form: FormGroup;
  get additionalFieldsForm(): any[] { return this.occtaxFormCountingService.additionalFieldsForm; };

  constructor(
    public occtaxFormService: OcctaxFormService,
    public occtaxFormOccurrenceService: OcctaxFormOccurrenceService,
    private occtaxFormCountingService: OcctaxFormCountingService,
    private occtaxFormCountingsService: OcctaxFormCountingsService,
  ) { }

  ngOnInit() {
    this.form = this.occtaxFormCountingService.form;
    this.sub = this.form.get("id_nomenclature_life_stage").valueChanges
      .filter(idNomenclatureLifeStage => idNomenclatureLifeStage !== null)
      .subscribe(idNomenclatureLifeStage => {      
        this.occtaxFormOccurrenceService.lifeStage.next(idNomenclatureLifeStage);
      });
  }

  ngOnDestroy() {
    //delete elem from form.get('cor_counting_occtax')
    const idx = (this.occtaxFormOccurrenceService.form.get('cor_counting_occtax') as FormArray).controls
                  .findIndex(elem => elem === this.form);
    if (idx !== -1) {
      (this.occtaxFormOccurrenceService.form.get('cor_counting_occtax') as FormArray).removeAt(idx);
    }
  }

  get taxref() {
    const taxref = this.occtaxFormOccurrenceService.taxref.getValue();
    return taxref;
  }

  defaultsMedia() {
    const occtaxData = this.occtaxFormService.occtaxData.getValue();
    const taxref = this.occtaxFormOccurrenceService.taxref.getValue();

    if (!(occtaxData && taxref)) {
      return {
        displayDetails: false,
      }
    }

    const observers = (occtaxData && occtaxData.releve.properties.observers) || [];
    const author = observers.map(o => o.nom_complet).join(', ');

    const date_min = (occtaxData && occtaxData.releve.properties.date_min) || null;


    const cd_nom = String(taxref && taxref.cd_nom) || '';
    const lb_nom = (taxref && `${taxref.lb_nom}`) || '';
    const date_txt = date_min ? `${date_min.year}_${date_min.month}_${date_min.day}` : ''
    const date_txt2 = date_min ? `${date_min.day}/${date_min.month}/${date_min.year}` : ''

    return {
      displayDetails: false,
      author: author,
      title_fr: `${date_txt}_${lb_nom.replace(' ', '_')}_${cd_nom}`,
      description_fr: `${lb_nom} observé le ${date_txt2}`,
    }
  }

}
