create view piir_eval.results_view as
select r.method_code, r.run_id, tr.start_time, tr.test_id, 
       tr.testrun_id, t.doc_id, t.corpus,
       'http://history-lab.org/documents/' || t.doc_id docurl,
       res.result_id, res.entity_code, res.entity_text, 
       '(' || entity_code || ', ' || entity_text || ')' entity_pair,
       res.start_idx, res.end_idx
   from piir_eval.runs r join piir_eval.testruns tr 
                              on (r.run_id = tr.run_id)
                         join piir_eval.tests t
                              on (tr.test_id = t.test_id)
                         left join piir_eval.results res
                              on (tr.testrun_id = res.testrun_id)
   where r.run_id = (select max(run_id)
                      from piir_eval.runs
                      where method_code = r.method_code);

create view piir_eval.cm_compare as
with muckrock (test_id, muckrock_cnt, muckrock_redactions) as 
              (select test_id, count(result_id), 
                      string_agg(entity_pair, ',' order by result_id)
                  from piir_eval.results_view
                  where method_code = 'muckrock'
                  group by test_id),
     capone   (test_id, capone_cnt, capone_redactions, drivers_license) as 
              (select test_id, count(result_id), 
                      string_agg(entity_pair, ',' order by result_id),
                      max(case when entity_code = 'drivers_license' then 'Y'
                               else 'N'
                          end) 
                  from piir_eval.results_view
                  where method_code = 'capone'
                  group by test_id),
     tests    (test_id, corpus, doc_id, doc_url) as
              (select t.test_id, t.corpus, t.doc_id,
                      'http://history-lab.org/documents/' || 
                      t.doc_id doc_url
                  from piir_eval.tests t 
                     join piir_eval.testsets ts 
                        on (t.testset_id = ts.testset_id)
                  where ts.name = 'cables-ssn')
select t.test_id, 
       case when capone_redactions = muckrock_redactions then 'Y'
            else 'N'
       end redactions_match,
       case when capone_cnt = muckrock_cnt then 'Y'
            else 'N'
       end cnts_match, 
       drivers_license, 
       capone_cnt, muckrock_cnt, 
       capone_redactions, muckrock_redactions,
       t.corpus, t.doc_id, 
       'http://history-lab.org/documents/' || t.doc_id doc_url
   from tests t left join capone c on (t.test_id = c.test_id)
                left join muckrock m on (t.test_id = m.test_id);

create or replace view piir_eval.capone_eval as
with capone (test_id, start_idx, end_idx, entity_code, entity_text, 
             start_time, doc_id, docurl) as 
            (select test_id, start_idx, end_idx, entity_code, entity_text, 
                    start_time, doc_id, docurl
               from piir_eval.results_view 
               where method_code = 'capone' and 
                     start_idx is not null)
select coalesce(gt.test_id, c.test_id) task_id, 
       gt.start_idx gt_start, gt.end_idx gt_end,
       c.start_idx co_start, c.end_idx co_end,
       gt.entity_code gt_entity, c.entity_code co_entity, 
       c.entity_text co_entity_text, 
       case when c.start_idx = gt.start_idx then 'TP'
            when gt.start_idx is null       then 'FP'
            when gt.start_idx is not null   then 'FN'
       end redaction_result,
       case when gt.entity_code = c.entity_code and
                 gt.start_idx = c.start_idx then 'TP'
            when gt.start_idx is null       then 'FP'
            when gt.start_idx is not null   then 'FN'
       end entity_result,
       start_time, doc_id, docurl
   from piir_eval.ground_truth gt full outer join capone c
     on (gt.test_id = c.test_id and gt.start_idx = c.start_idx)
   order by c.test_id, c.start_idx, gt.start_idx;

create or replace view piir_eval.muckrock_eval as
with muckrock (test_id, start_idx, end_idx, entity_code, entity_text, 
             start_time, doc_id, docurl) as 
            (select test_id, start_idx, end_idx, entity_code, entity_text, 
                    start_time, doc_id, docurl
               from piir_eval.results_view 
               where method_code = 'muckrock' and 
                     start_idx is not null)
select coalesce(gt.test_id, c.test_id) task_id, 
       gt.start_idx gt_start, gt.end_idx gt_end,
       c.start_idx mu_start, c.end_idx mu_end,
       gt.entity_code gt_entity, c.entity_code mu_entity, 
       c.entity_text mu_entity_text, 
       case when c.start_idx = gt.start_idx then 'TP'
            when gt.start_idx is null       then 'FP'
            when gt.start_idx is not null   then 'FN'
       end redaction_result,
       case when gt.entity_code = c.entity_code and
                 gt.start_idx = c.start_idx then 'TP'
            when gt.start_idx is null       then 'FP'
            when gt.start_idx is not null   then 'FN'
       end entity_result,
       start_time, doc_id, docurl
   from piir_eval.ground_truth gt full outer join muckrock c
     on (gt.test_id = c.test_id and gt.start_idx = c.start_idx)
   order by c.test_id, c.start_idx, gt.start_idx;

create or replace view piir_eval.ground_truth_view as
select gt.test_id task_id, gt.start_idx, gt.end_idx,
       gt.entity_code, gt.entity_text, t.doc_id, 
       'http://history-lab.org/documents/' || t.doc_id doc_url, 
       gt.label_studio_id, gt.creator, gt.completed,
       gt.ground_truth_id
     from piir_eval.ground_truth gt join piir_eval.tests t
          on (gt.test_id = t.test_id);