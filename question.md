1. type of container? 
    - free tier b1s?
    - 
2. workflow: 
    - terraform fmt validate
    - terraform plan
    - manuall accept merge to main and auto call
        - terraform apply (when manual accept to merge to main)
3. what is SG network? tags?
4. auto shutdown when which event was happenf?
5. Configure auth github -> azure. OIDC type without pass and secrets question in which sequence we need in this? 
    - posible in manual accept in merge to main and call teraform apply. but in which actins also?
6. не понял идею про ручной teraform destroy для экономии денег объясни
7. fallback by size and length  не понял к чему это , это про выбор типа контекйнера? но причем тогда размер и длина?
8. о какой проверке и обработке идет речь?
9. не понял чем spot отличается от фри тир 
10. auto shutdown по какому событию не понимаю
11. для чего в workflows описывается terraform.yml как тераформ относится к гитхаб воркфлоу и эта подпапка это возможности гитхаба складывать туда описание действий воркфлоу? есть документация? дай ссылку
12. как правилльно настраивать авторизацию oidc тоже документацию
13. plan  на pr что такое? это настройка? как она деается?
14. apply тоже что эо и как настраивается? это отдельный файл? конечно сначала будем проверять вручную, а потом на main + envir approval т.е. когда при пул реквесте  в мейн идет подтверждение тогда эпплай
15. destroy manual что он должен дестроить?
16. о каких тегах на ресурсы идет речь? что такое ресурсы и зачем им теги?
17. автошатадун по расписанию это не плохо, тоже хочу настроить


Terraform VM + netowrk + autoshutdown

объясни каждую строчку tf что ты описал почему такая где ссылка на документацию для чего нужны опции и параметры которые ты описал и почему выбрал именно такие варианты

составь для пункта 7 отдельно план чтобы минимально можно было проверить что это работает и вообще разбей обшую задачу на несколько различных чтобы я мог отдельно отладить и потом уже совместить

 8.3. не capacity guarantee.  объясни

 не понял идею для vm_size
---- between ---


 ----------- chatgpt explanation 2 question part

 1. 
