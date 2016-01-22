<?php
function netdev($devid,$mac,$if) {
   $txt = '';
   $txt .= $devid.'_MAC="'.res('mac',$if).'"'.NL;
   $txt .= $devid.'_DEV="$(find_nic $'.$devid.'_MAC)"'.NL;
   $txt .= '[ -z $'.$devid.'_DEV ] && fatal "Unable to find mac address $'.
      $devid.'_MAC"'.NL;
   return $txt;
}

?>
