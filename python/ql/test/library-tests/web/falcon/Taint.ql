
import python


import semmle.python.web.HttpRequest
import semmle.python.web.HttpResponse
import semmle.python.security.strings.Untrusted


from TaintedNode node
where node.getLocation().getFile().getName().matches("%falcon/test.py")
select node.getLocation().toString(), node.getNode().getNode().toString(), node.getTaintKind()

