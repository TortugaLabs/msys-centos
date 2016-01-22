<?php
//
function getgrps($url) {
   $url = preg_replace('/\/+$/','/',$url);
   $txt = file_get_contents($url."repodata/repomd.xml");
   if ($txt === false) return false;

   $type_group = false;
   $group_url = false;
   foreach (explode("\n",$txt) as $ln) {
      if (preg_match('/^\s*<data\s+type="([^"]+)"\s*>\s*$/',$ln,$mv)) {
	 $type_group = strtolower($mv[1]) == "group";
	 continue;
      }
      if ($type_group && preg_match('/^\s*<location\s+href="([^"]+)"/',$ln,$mv)) {
	 $group_url = $mv[1];
	 break;
      }
   }
   if ($group_url == false) return false;

   $comps_str = file_get_contents($url.$group_url);
   $id = '_';
   $grps = [];
   foreach (explode("\n",$comps_str) as $ln) {
      if (preg_match('/^\s*<id>(.+)<\/id>\s*$/',$ln,$mv)) {
	 $id = strtr($mv[1],['-'=>'_']);
	 continue;
      }
      if (preg_match('/^\s*<packagereq([^>]*)>(.*)<\/packagereq>\s*$/',$ln,$mv)) {
	 $pkgname = $mv[2];
	 $pkgattr = " ".$mv[1]." ";
	 $pkgtype = "default";
	 if (preg_match('/\s+type="([^"]+)"/',$pkgattr,$mv))
	    $pkgtype = $mv[1];

	 switch ($pkgtype) {
	    case "mandatory":
	       $ext = ["","_mand"];
	       break;
	    case "default":
	       $ext = ["","_def"];
	       break;
	    case "optional":
	       $ext = ["_opt"];
	       break;
	    case "conditional":
	       $ext = ["_cond"];
	       break;
	    default:
	       $ext = ["_".$pkgtype ];
	 }

	 foreach ($ext as $i) {
	    if (!isset($grps[$id.$i])) $grps[$id.$i] = [];
	    $grps[$id.$i][$pkgname] = $pkgname;
	 }
	 continue;
      }
   }
   return $grps;
}

function grpdefs($grps,$prefix = "_swg_") {
   $txt = '';
   foreach ($grps as $id => $dat) {
      $txt .= $prefix.$id."='".implode(" ",$dat)."'\n";
   }
   return $txt;
}

function mkgrps($basearch,$relver) {
   $swfile = dirname(realpath(__FILE__)).'/vardat/'.join('-',[
      'swcfg',$relver,$basearch]).'.sh';
   if (file_exists($swfile)) return file_get_contents($swfile);

   global $cf;
   if (isset($cf['globs']['comps'])) {
      $comps = $cf['globs']['comps'];
   } else {
      $comps = [ 'http://mirror.centos.org/centos/$releasever/os/$basearch/' ];
   }
   $macros = [
      '$basearch' => $basearch,
      '$releasever' => $relver,
   ];
   $txt = '';
   foreach ($comps as $url) {
      $url = strtr($url,$macros);
      $grdef = getgrps($url);
      if ($grdef === false) continue;
      $txt .= grpdefs($grdef);
   }
   file_put_contents($swfile,$txt);
   return $txt;
}

/*
$basearch = php_uname('m');
$relver = 7;

array_shift($argv);
while (count($argv)) {
   if ($argv[0] == '-m') {
      array_shift($argv);
      $basearch = array_shift($argv);
   } elseif ($argv[0] == '-v') {
      array_shift($argv);
      $relver = array_shift($argv);
      if ($relver) $relver = intval($relver);
   } else {
      die("Invalid option: ".$argv[0]."\n");
   }
}
if (!$basearch) die("No basearch specified\n");
if (!$relver) die("No release version specified\n");
*/
