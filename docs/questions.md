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
6. I didn't understand the idea of manual terraform destroy to save money, explain
7. fallback by size and length — I didn't understand what this is about, is it about choosing the container type? but then why size and length?
8. what kind of check and handling is being talked about?
9. I don't understand how spot differs from free tier
10. auto shutdown — I don't understand by which event
11. why is terraform.yml described in workflows, how does terraform relate to github workflow and is this subfolder a github feature for storing workflow action descriptions? is there documentation? give a link
12. how to properly set up oidc authorization — documentation too
13. plan on PR — what is that? is it a setting? how is it done?
14. apply — what is that and how is it configured? is it a separate file? of course first we'll check manually, then on main + environment approval, i.e. when a pull request to main gets confirmed, then apply
15. destroy manual — what should it destroy?
16. what tags on resources are being talked about? what are resources and why do they need tags?
17. auto shutdown on a schedule — that's not bad, I want to set it up too


Terraform VM + network + autoshutdown

explain every line of the tf you described, why it's that way, where is the documentation link, what the options and parameters you described are for, and why you chose those particular variants

make a separate plan for point 7 so that it can be minimally checked that this works, and split the overall task into several different ones so I can debug each separately and then combine them

 8.3. not a capacity guarantee. explain

 didn't understand the idea for vm_size
---- between ---


 ----------- chatgpt explanation 2 question part

 1.
